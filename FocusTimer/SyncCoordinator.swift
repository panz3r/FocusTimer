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

    private var pollTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastPushedLogHash: Int?
    private var lastPushedStatsHash: Int?

    /// Injectable so the merge/flush logic can be verified headlessly
    /// against a temp directory; the app singleton uses the real iCloud
    /// Drive folder.
    private let folderOverride: URL?

    init(folderOverride: URL? = nil) {
        self.folderOverride = folderOverride
        lastSyncAt = UserDefaults.standard.object(forKey: "icloud.lastSyncAt") as? Date
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

    // MARK: - Enablement & lifecycle

    /// First-use default follows plan: on when iCloud Drive is detected,
    /// off otherwise; an explicit toggle always wins afterwards.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "icloudSyncEnabled") as? Bool
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
        return try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: StatsStore.shared.sessionLog))
    }

    private func makeDailyStatsData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: StatsStore.shared.dailyStatsSnapshot))
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
                let result = StatsStore.shared.mergeImport(dailyStats: [:], sessionLog: entries)
                changed = changed || result.newSessions > 0
            }
        }
        if let data = readRemoteData(dailyStatsURL) {
            sawRemote = true
            if data.hashValue != lastPushedStatsHash,
               let days = decode([String: StatsStore.DaySnapshot].self, from: data) {
                let result = StatsStore.shared.mergeImport(dailyStats: days, sessionLog: [])
                changed = changed || result.changedDays > 0
            }
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
        UserDefaults.standard.set(lastSyncAt, forKey: "icloud.lastSyncAt")
    }
}

/// Versioned wrapper for every sync file.
struct SyncEnvelope<T: Codable>: Codable {
    let schemaVersion: Int
    let payload: T
}
