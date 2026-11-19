import Foundation

/// Area 3: multi-Mac sync of daily stats + session log through iCloud Drive.
/// Two JSON files in the user's iCloud Drive are the shared source of truth;
/// merges are max-of per day (daily stats) and union-by-UUID (session log),
/// so simultaneous edits on two Macs converge instead of losing data.
///
/// Implementation notes (deviations from the original plan, all deliberate):
/// - Direct-path access to ~/Library/Mobile Documents/com~apple~CloudDocs/
///   instead of FileManager.url(forUbiquityContainerIdentifier:) — that API
///   returns nil for unsigned local builds without iCloud entitlements,
///   while direct path access works fine with the sandbox off.
/// - Remote-change detection is a 15-second mtime/content poll plus a check
///   on app foreground, instead of NSMetadataQuery (whose ubiquitous scopes
///   are unreliable without entitlements). Polling follows the
///   DigestChecker/BackupScheduler pattern already in the codebase.
/// - No manifest.json: our own writes are recognized by content hash, which
///   is strictly more reliable than timestamp bookkeeping.
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    enum State: Equatable {
        case disabled
        case unconfigured
        case ready
        case syncing
        case error(String)
    }

    @Published private(set) var state: State = .disabled
    @Published private(set) var lastSyncAt: Date?
    /// A session currently running on ANOTHER Mac (own-host sessions are
    /// filtered out — the local UI already shows them).
    @Published private(set) var remoteActiveSession: ActiveSession?

    private var pollTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastPushedLogHash: Int?
    private var lastPushedStatsHash: Int?
    private var lastPushedCurrentHash: Int?

    /// Stable per-machine identity, so clients can tell their own writes
    /// from other Macs' and clean up their own stale files after a crash.
    private let deviceId: String
    private let deviceName: String

    /// Injectable folder + defaults + store so tests run fully isolated;
    /// the app singleton uses the real iCloud folder and `.standard`.
    private let folderOverride: URL?
    private let defaults: UserDefaults
    private let store: StatsStore

    init(folderOverride: URL? = nil, defaults: UserDefaults = .standard, store: StatsStore = .shared) {
        self.folderOverride = folderOverride
        self.defaults = defaults
        self.store = store
        lastSyncAt = defaults.object(forKey: "icloud.lastSyncAt") as? Date

        if let saved = defaults.string(forKey: "sync.deviceId") {
            deviceId = saved
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: "sync.deviceId")
            deviceId = fresh
        }
        deviceName = Host.current().localizedName ?? "Mac"
    }

    // MARK: - Paths

    private static let cloudDocsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

    /// User-visible as "iCloud Drive / FocusTimer" in Finder.
    static var syncFolder: URL {
        cloudDocsRoot.appendingPathComponent("FocusTimer", isDirectory: true)
    }

    static var iCloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: cloudDocsRoot.path)
    }

    private var syncFolder: URL { folderOverride ?? Self.syncFolder }
    private var sessionLogURL: URL { syncFolder.appendingPathComponent("session-log.json") }
    private var dailyStatsURL: URL { syncFolder.appendingPathComponent("daily-stats.json") }
    private var currentSessionURL: URL { syncFolder.appendingPathComponent("current-session.json") }

    // MARK: - Enablement & lifecycle

    /// First-use default follows plan: on when iCloud Drive is detected,
    /// off otherwise; an explicit toggle always wins afterwards.
    var isEnabled: Bool {
        defaults.object(forKey: "icloudSyncEnabled") as? Bool
            ?? Self.iCloudDriveAvailable
    }

    func restartIfNeeded() {
        isEnabled ? start() : stop()
    }

    func start() {
        guard pollTimer == nil else { return }
        if folderOverride == nil {
            guard Self.iCloudDriveAvailable else {
                state = .unconfigured
                return
            }
        }
        do {
            try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        } catch {
            state = .error("Couldn't create sync folder: \(error.localizedDescription)")
            return
        }
        state = .ready
        pullFromRemote()

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.pollRemote()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        state = .disabled
    }

    /// Fast recovery after sleep / long inactivity.
    func appDidBecomeActive() {
        guard isRunning else { return }
        pollRemote()
    }

    private var isRunning: Bool { pollTimer != nil }

    // MARK: - Write path

    /// Debounced push after a local change (5-second window coalesces
    /// bursts). Never blocks the timer; failures surface in Settings only.
    func queueWrite() {
        guard isEnabled, isRunning else { return }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Synchronous push of local state to iCloud Drive (quit path, "Sync
    /// now", and the debounced write all land here).
    func flushNow() {
        guard isEnabled else { return }
        flush()
    }

    func syncNow() {
        guard isEnabled else { return }
        pullFromRemote()
        flush()
    }

    private func flush() {
        guard isEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        } catch {
            state = .error("Couldn't create sync folder: \(error.localizedDescription)")
            return
        }

        let logData: Data
        let statsData: Data
        do {
            logData = try makeSessionLogData()
            statsData = try makeDailyStatsData()
        } catch {
            state = .error("Couldn't encode stats: \(error.localizedDescription)")
            return
        }

        let logHash = logData.hashValue
        let statsHash = statsData.hashValue
        if logHash == lastPushedLogHash, statsHash == lastPushedStatsHash {
            return   // nothing changed since the last push
        }

        do {
            try logData.write(to: sessionLogURL, options: .atomic)
            try statsData.write(to: dailyStatsURL, options: .atomic)
        } catch {
            state = .error("Couldn't write to iCloud Drive: \(error.localizedDescription)")
            return
        }

        lastPushedLogHash = logHash
        lastPushedStatsHash = statsHash
        markSynced()
    }

    private func makeSessionLogData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: store.sessionLog))
    }

    private func makeDailyStatsData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: store.dailyStatsSnapshot))
    }

    // MARK: - Current session (live state across Macs)

    /// Mirrors a locally started/paused session to current-session.json, or
    /// removes the file when the session ends (completed, skipped, reset).
    /// Identity (host/deviceId) is owned by the coordinator.
    func pushCurrentSession(id: UUID, type: String, label: String,
                            startedAt: Date, durationSeconds: Int, paused: Bool) {
        pushCurrentSession(ActiveSession(
            id: id,
            host: deviceName,
            type: type,
            label: label,
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            pausedAt: paused ? Date() : nil
        ))
    }

    /// Mirrors a locally started/paused session to current-session.json, or
    /// removes the file when the session ends (completed, skipped, reset).
    func pushCurrentSession(_ session: ActiveSession?) {
        guard isEnabled, Self.iCloudDriveAvailable else { return }
        do {
            if let session {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: session))
                try data.write(to: currentSessionURL, options: .atomic)
                lastPushedCurrentHash = data.hashValue
            } else {
                try? FileManager.default.removeItem(at: currentSessionURL)
                lastPushedCurrentHash = nil
            }
        } catch {
            state = .error("Couldn't sync current session: \(error.localizedDescription)")
        }
    }

    /// Removes our own stale current-session file after a crash (a file
    /// written by another Mac is left alone — it expires on its own).
    func clearOwnSessionIfAny() {
        guard let data = readRemoteData(currentSessionURL),
              let session = decode(ActiveSession.self, from: data),
              session.host == deviceName || session.host == deviceId else { return }
        try? FileManager.default.removeItem(at: currentSessionURL)
        lastPushedCurrentHash = nil
    }

    // MARK: - Read path

    private func pollRemote() {
        pullFromRemote()
    }

    /// Merges remote content into the local store. Idempotent: our own
    /// writes are recognized by content hash and skipped, so no loop.
    @discardableResult
    private func pullFromRemote() -> Bool {
        guard isEnabled else { return false }
        switch state {
        case .ready, .error: break
        default: return false
        }

        var changed = false
        var sawRemote = false

        if let data = readRemoteData(sessionLogURL) {
            sawRemote = true
            if data.hashValue != lastPushedLogHash,
               let entries = decode([StatsStore.SessionEntry].self, from: data) {
                let result = store.mergeImport(dailyStats: [:], sessionLog: entries)
                changed = changed || result.newSessions > 0
            }
        }
        if let data = readRemoteData(dailyStatsURL) {
            sawRemote = true
            if data.hashValue != lastPushedStatsHash,
               let days = decode([String: StatsStore.DaySnapshot].self, from: data) {
                let result = store.mergeImport(dailyStats: days, sessionLog: [])
                changed = changed || result.changedDays > 0
            }
        }

        // Current session awareness: a session running on another Mac.
        // Own-host sessions are ignored (the local UI shows them already);
        // expired ones are ignored (the owner will delete the file).
        if let data = readRemoteData(currentSessionURL) {
            sawRemote = true
            if let session = decode(ActiveSession.self, from: data),
               !session.isExpired,
               session.host != deviceName, session.host != deviceId {
                remoteActiveSession = session
            } else {
                remoteActiveSession = nil
            }
        } else {
            remoteActiveSession = nil
        }

        guard sawRemote else { return false }

        if changed {
            markSynced()
            flush()   // push the merged superset back so both sides converge
        }
        return changed
    }

    /// Reads a remote file, or nil when it's missing, undecodable-by-US (not
    /// present yet), or evicted by iCloud Drive (download re-requested for
    /// the next poll).
    private func readRemoteData(_ url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = values?.ubiquitousItemDownloadingStatus, status != .current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func decode<T: Codable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SyncEnvelope<T>.self, from: data).payload
    }

    private func markSynced() {
        if case .syncing = state { state = .ready } else { state = .ready }
        lastSyncAt = Date()
        defaults.set(lastSyncAt, forKey: "icloud.lastSyncAt")
    }
}

/// Versioned wrapper for every sync file.
struct SyncEnvelope<T: Codable>: Codable {
    let schemaVersion: Int
    let payload: T
}

/// Snapshot of a session running on some Mac, mirrored to
/// current-session.json. Created on start, rewritten on pause/resume,
/// deleted when the session ends. Other clients derive the remaining time
/// from startedAt — no per-second writes.
struct ActiveSession: Codable {
    let id: UUID
    let host: String
    let type: String              // SessionType raw value
    let label: String
    let startedAt: Date
    let durationSeconds: Int
    var pausedAt: Date?           // set while the session is paused

    /// Seconds left, derived from the clock. Paused sessions freeze at the
    /// moment they were paused.
    var remainingSeconds: Int {
        let reference = pausedAt ?? Date()
        let elapsed = Int(reference.timeIntervalSince(startedAt))
        return max(0, durationSeconds - elapsed)
    }

    /// A session nobody is running anymore: its time elapsed, or it has
    /// been paused for over a day. Lets every client ignore stale files
    /// (un-propagated deletions, crashed machines) without coordination.
    var isExpired: Bool {
        if let pausedAt {
            return Date().timeIntervalSince(pausedAt) > 86_400
        }
        return Date().timeIntervalSince(startedAt) > Double(durationSeconds + 60)
    }
}
