import Foundation

private struct DayRecord: Codable {
    var sessions: Int = 0
    var focusMinutes: Int = 0
}

final class StatsStore {
    static let shared = StatsStore()

    private let udKey = "v1_daily_stats"
    private var records: [String: DayRecord]

    private init() {
        if let data = UserDefaults.standard.data(forKey: udKey),
           let decoded = try? JSONDecoder().decode([String: DayRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
        let logData = UserDefaults.standard.data(forKey: "v1_session_log")
        if let data = logData,
           let decoded = try? JSONDecoder().decode([SessionEntry].self, from: data) {
            sessionLog = decoded
        } else {
            sessionLog = []
        }
    }

    var todaySessions: Int     { records[todayKey]?.sessions     ?? 0 }
    var todayFocusMinutes: Int { records[todayKey]?.focusMinutes ?? 0 }

    var weekSessions: Int {
        let cal = Calendar.current
        return (0..<7).reduce(0) { sum, i in
            guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { return sum }
            return sum + (records[key(for: d)]?.sessions ?? 0)
        }
    }

    var currentStreak: Int {
        let cal = Calendar.current
        var streak = 0
        var date = Date()

        if todaySessions > 0 {
            streak = 1
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = prev
            guard (records[key(for: date)]?.sessions ?? 0) > 0 else { return 0 }
            streak = 1
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }

        while true {
            guard (records[key(for: date)]?.sessions ?? 0) > 0,
                  let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            streak += 1
            date = prev
        }
        return streak
    }

    struct DayStat {
        let date: Date
        let sessions: Int
        let focusMinutes: Int
        var isToday: Bool { Calendar.current.isDateInToday(date) }
    }

    func history(days n: Int) -> [DayStat] {
        let cal = Calendar.current
        return (0..<n).compactMap { i -> DayStat? in
            guard let d = cal.date(byAdding: .day, value: -(n - 1 - i), to: Date()) else { return nil }
            let r = records[key(for: d)] ?? DayRecord()
            return DayStat(date: d, sessions: r.sessions, focusMinutes: r.focusMinutes)
        }
    }

    // MARK: - Session log

    struct SessionEntry: Codable, Identifiable {
        var id: UUID = UUID()
        let timestamp: Date
        let durationMinutes: Int
        let taskLabel: String
        /// Active schedule step label; nil for entries recorded before
        /// schedules exist (Area 4). Optional so old stores and backups decode.
        var stepLabel: String? = nil
    }

    private let logKey = "v1_session_log"
    private(set) var sessionLog: [SessionEntry]

    func recentEntries(days: Int) -> [SessionEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sessionLog.filter { $0.timestamp >= cutoff }
    }

    func recentLabels(limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in sessionLog.reversed() {
            let label = entry.taskLabel.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !seen.contains(label) else { continue }
            seen.insert(label)
            result.append(label)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Record

    var allTimeSessions:    Int { records.values.reduce(0) { $0 + $1.sessions } }
    var allTimeFocusMinutes: Int { records.values.reduce(0) { $0 + $1.focusMinutes } }

    func recordSession(durationMinutes: Int, taskLabel: String = "", stepLabel: String? = nil) {
        var record = records[todayKey] ?? DayRecord()
        record.sessions += 1
        record.focusMinutes += durationMinutes
        records[todayKey] = record

        let entry = SessionEntry(timestamp: Date(), durationMinutes: durationMinutes, taskLabel: taskLabel, stepLabel: stepLabel)
        sessionLog.append(entry)
        // Area 1: no in-memory cap — the store is the source of truth.
        persistLog()
        persist()

        checkMilestone(totalSessions: allTimeSessions)
    }

    // MARK: - Milestones

    private static let milestones = [10, 50, 100, 500, 1000]
    private static let milestoneKey = "v1_milestones_reached"

    private func checkMilestone(totalSessions: Int) {
        var reached = Set(UserDefaults.standard.array(forKey: Self.milestoneKey) as? [Int] ?? [])
        let unfired = Self.milestones.filter { totalSessions >= $0 && !reached.contains($0) }
        guard let highest = unfired.max() else { return }
        unfired.forEach { reached.insert($0) }
        UserDefaults.standard.set(Array(reached), forKey: Self.milestoneKey)
        NotificationManager.shared.sendMilestone(sessions: highest, focusMinutes: allTimeFocusMinutes)
    }

    private var todayKey: String { Self.todayKey }

    // MARK: - Export / import (Area 1)

    struct DaySnapshot: Codable {
        var sessions: Int
        var focusMinutes: Int
    }

    /// All daily counters keyed by canonical "yyyy-MM-dd", for backup export.
    var dailyStatsSnapshot: [String: DaySnapshot] {
        records.mapValues { DaySnapshot(sessions: $0.sessions, focusMinutes: $0.focusMinutes) }
    }

    /// Current stored counters for a canonical day key ("yyyy-MM-dd").
    func dayStats(for dayKey: String) -> DaySnapshot {
        let r = records[dayKey] ?? DayRecord()
        return DaySnapshot(sessions: r.sessions, focusMinutes: r.focusMinutes)
    }

    /// Current stored counters for the day containing `date`.
    func dayRecord(for date: Date) -> DaySnapshot {
        dayStats(for: key(for: date))
    }

    /// Merge-import (Area 1): per-day max-of, log union by id. Idempotent —
    /// importing the same backup twice is a no-op the second time.
    /// Milestones are deliberately not re-checked here; they fire on live
    /// sessions only.
    @discardableResult
    func mergeImport(dailyStats: [String: DaySnapshot], sessionLog incoming: [SessionEntry]) -> (newSessions: Int, changedDays: Int) {
        var changedDays = 0
        for (day, inc) in dailyStats {
            let existing = records[day] ?? DayRecord()
            let merged = DayRecord(
                sessions: max(existing.sessions, inc.sessions),
                focusMinutes: max(existing.focusMinutes, inc.focusMinutes)
            )
            if merged.sessions != existing.sessions || merged.focusMinutes != existing.focusMinutes {
                records[day] = merged
                changedDays += 1
            }
        }
        let known = Set(sessionLog.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }
        if !fresh.isEmpty {
            sessionLog.append(contentsOf: fresh)
            sessionLog.sort { $0.timestamp < $1.timestamp }
        }
        persist()
        persistLog()
        return (fresh.count, changedDays)
    }

    /// Day key for "now" in the store's canonical format. Exposed so
    /// TimerViewModel can detect day rollover (Item 0) without reaching
    /// into private store state.
    static var todayKey: String { key(for: Date()) }

    private func key(for date: Date) -> String {
        Self.key(for: date)
    }

    private static func key(for date: Date) -> String {
        DateFormatter.yyyyMMdd.string(from: date)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    private func persistLog() {
        if let data = try? JSONEncoder().encode(sessionLog) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }
}

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
}
