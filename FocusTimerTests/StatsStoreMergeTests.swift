import Testing
import Foundation
@testable import FocusTimer

/// Areas 1 & 4: StatsStore merge semantics + session recording.
@Suite("Stats Store Merge & Recording")
struct StatsStoreMergeTests {

    private func makeStore() -> (StatsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test-stats-\(UUID().uuidString)")!
        return (StatsStore(defaults: defaults), defaults)
    }

    private func entry(_ id: String, minutes: Int = 25, label: String = "") -> StatsStore.SessionEntry {
        StatsStore.SessionEntry(
            id: UUID(uuidString: id)!,
            timestamp: Date(timeIntervalSince1970: 915148800),   // 1999-01-01
            durationMinutes: minutes,
            taskLabel: label
        )
    }

    @Test func dailyStatsMergeTakesMax() {
        let (store, _) = makeStore()
        store.mergeImport(
            dailyStats: [
                "1999-01-01": .init(sessions: 5, focusMinutes: 100),
                "1999-01-02": .init(sessions: 1, focusMinutes: 20)
            ],
            sessionLog: []
        )
        // Local has more on 01-01; remote has more on 01-02.
        store.mergeImport(
            dailyStats: [
                "1999-01-01": .init(sessions: 2, focusMinutes: 50),
                "1999-01-02": .init(sessions: 4, focusMinutes: 80)
            ],
            sessionLog: []
        )
        #expect(store.dayStats(for: "1999-01-01").sessions == 5)
        #expect(store.dayStats(for: "1999-01-01").focusMinutes == 100)
        #expect(store.dayStats(for: "1999-01-02").sessions == 4)
        #expect(store.dayStats(for: "1999-01-02").focusMinutes == 80)
    }

    @Test func sessionLogMergeUnionsByID() {
        let (store, _) = makeStore()
        let a = entry("AAAAAAAA-BBBB-CCCC-DDDD-000000000001")
        let b = entry("AAAAAAAA-BBBB-CCCC-DDDD-000000000002")

        store.mergeImport(dailyStats: [:], sessionLog: [a])
        store.mergeImport(dailyStats: [:], sessionLog: [a, b])   // a is a duplicate

        #expect(store.sessionLog.count == 2)
        #expect(Set(store.sessionLog.map(\.id)) == Set([a.id, b.id]))
    }

    @Test func importIsIdempotent() {
        let (store, _) = makeStore()
        let backup: [StatsStore.SessionEntry] = [
            entry("AAAAAAAA-BBBB-CCCC-DDDD-000000000001", label: "one"),
            entry("AAAAAAAA-BBBB-CCCC-DDDD-000000000002", label: "two")
        ]
        let days: [String: StatsStore.DaySnapshot] = ["1999-01-01": .init(sessions: 3, focusMinutes: 75)]

        let first = store.mergeImport(dailyStats: days, sessionLog: backup)
        let countAfterFirst = store.sessionLog.count
        let second = store.mergeImport(dailyStats: days, sessionLog: backup)

        #expect(first.newSessions == 2 && first.changedDays == 1)
        #expect(second.newSessions == 0 && second.changedDays == 0)
        #expect(store.sessionLog.count == countAfterFirst)
    }

    @Test func recordSessionCarriesStepLabel() {
        let (store, _) = makeStore()
        store.recordSession(durationMinutes: 25, taskLabel: "writing", stepLabel: "Focus")
        #expect(store.sessionLog.count == 1)
        #expect(store.sessionLog[0].stepLabel == "Focus")
        #expect(store.sessionLog[0].taskLabel == "writing")
        #expect(store.todaySessions == 1)
    }

    @Test func importDoesNotFireMilestones() {
        let (store, defaults) = makeStore()
        // Import 10 sessions (crosses the first milestone threshold), with
        // matching daily stats so allTimeSessions reflects them.
        let entries = (1...10).map {
            entry(String(format: "AAAAAAAA-BBBB-CCCC-DDDD-0000000000%02d", $0))
        }
        let days = (1...10).reduce(into: [String: StatsStore.DaySnapshot]()) { result, i in
            result["1999-01-\(String(format: "%02d", i))"] = .init(sessions: 1, focusMinutes: 25)
        }
        store.mergeImport(dailyStats: days, sessionLog: entries)
        // Milestones fire on live sessions only — no marker recorded.
        #expect(defaults.array(forKey: "v1_milestones_reached") == nil)
        #expect(store.allTimeSessions == 10)
    }
}
