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

    private init() {
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
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeKey)
    }

    func delete(id: UUID) {
        guard schedules.count > 1, id != activeScheduleId else { return }
        schedules.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence & migration

    private func persist() {
        if let data = try? JSONEncoder().encode(schedules) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
        if let id = activeScheduleId {
            UserDefaults.standard.set(id.uuidString, forKey: Self.activeKey)
        }
    }

    private func bootstrap() {
        let ud = UserDefaults.standard

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
            return
        }

        // First launch after Area 4: migrate the legacy Pomodoro settings
        // into a schedule, then seed the built-in presets.
        let work   = ud.integer(forKey: "workDuration")
        let short  = ud.integer(forKey: "shortBreakDuration")
        let long   = ud.integer(forKey: "longBreakDuration")
        let cadence = ud.integer(forKey: "sessionsBeforeLongBreak")

        schedules = Schedule.seedPresets
        schedules[0] = Schedule.legacyPomodoro(
            work: work > 0 ? work : 25,
            shortBreak: short > 0 ? short : 5,
            longBreakMinutes: long > 0 ? long : 15,
            cadence: cadence > 0 ? cadence : 4
        )
        activeScheduleId = schedules.first?.id
        persist()
        ud.set(true, forKey: Self.migratedKey)
    }
}
