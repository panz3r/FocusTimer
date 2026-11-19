import Foundation

/// Area 4: persistence + active-schedule management for schedules.
/// Stored as JSON at UserDefaults["schedules.v1"]; the active id sits in
/// UserDefaults["schedules.active"].
///
/// First-launch bootstrap (legacy migration): builds a "Pomodoro" schedule
/// from the pre-Area-4 UserDefaults keys (workDuration / shortBreakDuration /
/// longBreakDuration / sessionsBeforeLongBreak) and seeds the built-in
/// presets. Guarded by a one-shot flag, so it never runs twice.
final class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()

    @Published private(set) var schedules: [Schedule] = []
    @Published private(set) var activeScheduleId: UUID?

    private static let storeKey = "schedules.v1"
    private static let activeKey = "schedules.active"
    private static let migratedKey = "schedules.migrated_v1"
    private static let goalMigrationKey = "schedules.goalPerSchedule_v4"

    private let defaults: UserDefaults

    /// Injectable defaults so tests run in an isolated domain; the app
    /// singleton uses `.standard` (behavior unchanged).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bootstrap()
    }

    var active: Schedule? {
        schedules.first { $0.id == activeScheduleId } ?? schedules.first
    }

    func schedule(id: UUID) -> Schedule? {
        schedules.first { $0.id == id }
    }

    /// Inserts or updates a schedule (the ViewModel's active copy edits land
    /// here through its didSet).
    func save(_ schedule: Schedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        persist()
    }

    func setActive(id: UUID) {
        guard schedules.contains(where: { $0.id == id }) else { return }
        activeScheduleId = id
        defaults.set(id.uuidString, forKey: Self.activeKey)
    }

    func delete(id: UUID) {
        guard schedules.count > 1, id != activeScheduleId else { return }
        schedules.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence & migration

    private func persist() {
        if let data = try? JSONEncoder().encode(schedules) {
            defaults.set(data, forKey: Self.storeKey)
        }
        if let id = activeScheduleId {
            defaults.set(id.uuidString, forKey: Self.activeKey)
        }
    }

    private func bootstrap() {
        let ud = defaults

        if let data = ud.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([Schedule].self, from: data),
           !decoded.isEmpty {
            schedules = decoded
            if let saved = ud.string(forKey: Self.activeKey),
               let id = UUID(uuidString: saved),
               decoded.contains(where: { $0.id == id }) {
                activeScheduleId = id
            } else {
                activeScheduleId = schedules.first?.id
            }
            applyPerScheduleGoalMigrationIfNeeded()
            return
        }

        // First launch after Area 4: migrate the legacy Pomodoro settings
        // into a schedule, then seed the built-in presets.
        let work   = ud.integer(forKey: "workDuration")
        let short  = ud.integer(forKey: "shortBreakDuration")
        let long   = ud.integer(forKey: "longBreakDuration")
        let cadence = ud.integer(forKey: "sessionsBeforeLongBreak")
        let legacyGoal = ud.object(forKey: "dailyGoal") as? Int ?? 8

        var seeded = Schedule.seedPresets
        seeded[0] = Schedule.legacyPomodoro(
            work: work > 0 ? work : 25,
            shortBreak: short > 0 ? short : 5,
            longBreakMinutes: long > 0 ? long : 15,
            cadence: cadence > 0 ? cadence : 4
        )
        schedules = seeded.map { schedule in
            var updated = schedule
            updated.dailyGoal = legacyGoal
            return updated
        }
        activeScheduleId = schedules.first?.id
        persist()
        ud.set(true, forKey: Self.migratedKey)
        ud.set(true, forKey: Self.goalMigrationKey)
    }

    /// Area 4 follow-up: the daily goal moved from a global setting to a
    /// per-schedule field. One-shot: seed every stored schedule with the
    /// legacy global goal so the user's target carries over (they can then
    /// differentiate per schedule). Required migration — preserves data.
    private func applyPerScheduleGoalMigrationIfNeeded() {
        let ud = UserDefaults.standard
        guard ud.object(forKey: Self.goalMigrationKey) == nil else { return }
        let legacyGoal = ud.object(forKey: "dailyGoal") as? Int ?? 8
        schedules = schedules.map { schedule in
            var updated = schedule
            updated.dailyGoal = legacyGoal
            return updated
        }
        persist()
        ud.set(true, forKey: Self.goalMigrationKey)
    }
}
