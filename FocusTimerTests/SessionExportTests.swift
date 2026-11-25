import Testing
import Foundation
@testable import FocusTimer

/// Area 1: export formats + import diffing.
@Suite("Session Export Formats")
struct SessionExportTests {

    private func makeStore() -> StatsStore {
        let store = StatsStore(defaults: UserDefaults(suiteName: "test-export-\(UUID().uuidString)")!)
        store.recordSession(durationMinutes: 25, taskLabel: "has \"quotes\", and, commas", stepLabel: "Focus", scheduleName: "Deep Work")
        store.recordSession(durationMinutes: 30, taskLabel: "plain", stepLabel: "Focus", scheduleName: "Pomodoro")
        return store
    }

    @Test func jsonEnvelopeRoundTrip() throws {
        let store = makeStore()
        let data = try SessionExport.makeJSONData(store: store)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        #expect(payload.schemaVersion == 1)
        #expect(payload.kind == "focus-timer.backup")
        #expect(payload.sessionLog.count == 2)
        #expect(payload.dailyStats.count >= 1)
        #expect(payload.sessionLog.first?.stepLabel == "Focus")
    }

    @Test func csvQuotesPerRFC4180() {
        let store = makeStore()
        let csv = String(data: SessionExport.makeCSVData(store: store), encoding: .utf8)!
        let lines = csv.split(separator: "\n").map(String.init)

        #expect(lines[0] == "timestamp,kind,schedule,duration_minutes,task_label")
        #expect(lines.count == 3)                                  // header + 2 sessions
        #expect(lines[1].contains("Deep Work"))                    // schedule snapshot
        #expect(lines[1].contains("\"has \"\"quotes\"\", and, commas\""))
        #expect(lines[1].contains(",work,"))                       // kind column
    }

    @Test func markdownContainsTableAndTotals() {
        let store = makeStore()
        let md = String(data: SessionExport.makeMarkdownData(store: store, days: 7), encoding: .utf8)!

        #expect(md.contains("| Day | Sessions | Focus time | Streak |"))
        #expect(md.contains("**Totals:** 2 sessions, 55m focus time."))
        #expect(md.contains("FocusTimer v"))                       // generated-by footer
    }

    @Test func diffCountsNewSessionsAndNewDays() {
        let from = StatsStore(defaults: UserDefaults(suiteName: "test-diff-\(UUID().uuidString)")!)
        from.recordSession(durationMinutes: 25, taskLabel: "x", stepLabel: "Focus")
        from.mergeImport(dailyStats: ["1999-01-01": .init(sessions: 5, focusMinutes: 100)], sessionLog: [])

        let target = makeStore()   // 2 sessions today (stronger than `from`'s today)
        let payload = SessionExport.makeBackupPayload(store: from)
        let diff = SessionExport.diff(for: payload, store: target)

        #expect(diff.newSessions == 1)   // `from`'s session UUID is new to target
        #expect(diff.changedDays == 1)   // 1999-01-01 is new; today is weaker -> skipped
    }
}
