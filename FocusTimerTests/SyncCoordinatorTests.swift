import Testing
import Foundation
@testable import FocusTimer

/// Area 3: SyncCoordinator convergence + current-session lifecycle,
/// verified against an injected temp folder and isolated store/defaults.
@Suite("Sync Coordinator")
struct SyncCoordinatorTests {

    private func makeEnvironment() -> (SyncCoordinator, StatsStore, URL) {
        let defaults = UserDefaults(suiteName: "test-sync-\(UUID().uuidString)")!
        defaults.set(true, forKey: "icloudSyncEnabled")   // explicit opt-in
        let store = StatsStore(defaults: defaults)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coordinator = SyncCoordinator(folderOverride: folder, defaults: defaults, store: store)
        return (coordinator, store, folder)
    }

    private func entry(_ suffix: String, minutes: Int = 25) -> StatsStore.SessionEntry {
        StatsStore.SessionEntry(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-0000000000\(suffix)")!,
            timestamp: Date(timeIntervalSince1970: 915148800),   // 1999-01-01
            durationMinutes: minutes,
            taskLabel: "seeded"
        )
    }

    private func seedRemote(_ folder: URL, entries: [StatsStore.SessionEntry],
                            days: [String: StatsStore.DaySnapshot]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: entries))
            .write(to: folder.appendingPathComponent("session-log.json"))
        try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: days))
            .write(to: folder.appendingPathComponent("daily-stats.json"))
    }

    @Test func convergenceSeedMergePushSuperset() throws {
        let (coordinator, store, folder) = makeEnvironment()
        try seedRemote(
            folder,
            entries: [entry("01")],
            days: ["1999-01-01": .init(sessions: 2, focusMinutes: 50)]
        )

        coordinator.start()
        defer { coordinator.stop() }

        // Remote content merged into the local store...
        #expect(store.dayStats(for: "1999-01-01").sessions == 2)
        #expect(store.sessionLog.count == 1)

        // ...local-only data pushed back (superset on both sides).
        store.mergeImport(
            dailyStats: ["1999-01-02": .init(sessions: 1, focusMinutes: 30)],
            sessionLog: [entry("02")]
        )
        coordinator.flushNow()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteLog = try decoder.decode(
            SyncEnvelope<[StatsStore.SessionEntry]>.self,
            from: Data(contentsOf: folder.appendingPathComponent("session-log.json"))
        ).payload
        #expect(remoteLog.count == 2)

        // Re-sync is a no-op (no duplicates).
        coordinator.syncNow()
        #expect(store.sessionLog.count == 2)
    }

    @Test func currentSessionLifecycle() throws {
        let (coordinator, _, folder) = makeEnvironment()
        coordinator.start()
        defer { coordinator.stop() }

        // Another Mac starts a session -> surfaced.
        let session = ActiveSession(
            id: UUID(), host: "other-mac", type: "Work", label: "remote",
            startedAt: Date(), durationSeconds: 1500, pausedAt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: session))
            .write(to: folder.appendingPathComponent("current-session.json"))
        coordinator.syncNow()
        #expect(coordinator.remoteActiveSession?.host == "other-mac")
        #expect(coordinator.remoteActiveSession!.remainingSeconds > 1400)

        // Owner ends it (file removed) -> awareness clears.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("current-session.json"))
        coordinator.syncNow()
        #expect(coordinator.remoteActiveSession == nil)
    }

    @Test func expiredAndPausedSessions() throws {
        let (coordinator, _, folder) = makeEnvironment()
        coordinator.start()
        defer { coordinator.stop() }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Expired: started 2h ago, 25 min duration -> ignored.
        let expired = ActiveSession(
            id: UUID(), host: "other-mac", type: "Work", label: "stale",
            startedAt: Date(timeIntervalSinceNow: -7200), durationSeconds: 1500, pausedAt: nil
        )
        try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: expired))
            .write(to: folder.appendingPathComponent("current-session.json"))
        coordinator.syncNow()
        #expect(coordinator.remoteActiveSession == nil)

        // Paused: remaining frozen at the paused moment (10 min elapsed of 25).
        let pauseDate = Date()
        let paused = ActiveSession(
            id: UUID(), host: "other-mac", type: "Work", label: "paused",
            startedAt: pauseDate.addingTimeInterval(-600),
            durationSeconds: 1500,
            pausedAt: pauseDate
        )
        try encoder.encode(SyncEnvelope(schemaVersion: 1, payload: paused))
            .write(to: folder.appendingPathComponent("current-session.json"))
        coordinator.syncNow()
        #expect(coordinator.remoteActiveSession?.remainingSeconds == 900)
    }

    @Test func ownSessionIsNotSurfaced() throws {
        let (coordinator, _, folder) = makeEnvironment()
        coordinator.start()
        defer { coordinator.stop() }

        // This Mac's own session (host = its own device name) never shows
        // up as "running elsewhere".
        coordinator.pushCurrentSession(
            id: UUID(), type: "Work", label: "mine",
            startedAt: Date(), durationSeconds: 1500, paused: false
        )
        coordinator.syncNow()
        #expect(coordinator.remoteActiveSession == nil)

        // But the file exists (other Macs will see it).
        #expect(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("current-session.json").path
        ))
    }
}
