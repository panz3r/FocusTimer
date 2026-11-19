import Testing
import Foundation
@testable import FocusTimer

/// Area 4: ScheduleStore bootstrap/migration + Schedule's tolerant decoding.
/// Each test uses a fresh isolated defaults suite.
@Suite("Schedule Store & Migration")
@MainActor
struct ScheduleStoreMigrationTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "test-schedules-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func legacyBootstrapMigration() {
        let defaults = makeDefaults()
        defaults.set(30, forKey: "workDuration")
        defaults.set(6, forKey: "shortBreakDuration")
        defaults.set(20, forKey: "longBreakDuration")
        defaults.set(3, forKey: "sessionsBeforeLongBreak")
        defaults.set(5, forKey: "dailyGoal")

        let store = ScheduleStore(defaults: defaults)
        let pomodoro = store.active!

        #expect(pomodoro.name == "Pomodoro")
        #expect(pomodoro.steps.count == 2)
        #expect(pomodoro.steps[0].label == "Work")     // traditional term kept
        #expect(pomodoro.steps[0].minutes == 30)
        #expect(pomodoro.steps[1].minutes == 6)
        #expect(pomodoro.longBreak?.minutes == 20)
        #expect(pomodoro.insertedLongBreakEvery == 3)
        #expect(pomodoro.dailyGoal == 5)               // legacy goal carried
        #expect(store.schedules.count >= 4)            // + seeded presets
        #expect(defaults.data(forKey: "schedules.v1") != nil)
    }

    @Test func existingStoreLoadsAndIsNotReseeded() throws {
        let defaults = makeDefaults()
        let custom = Schedule(name: "Custom Thing", steps: [Step(label: "Focus", minutes: 42, kind: .work)])
        let data = try JSONEncoder().encode([custom])
        defaults.set(data, forKey: "schedules.v1")
        defaults.set(custom.id.uuidString, forKey: "schedules.active")

        let store = ScheduleStore(defaults: defaults)
        #expect(store.schedules.count == 1)                    // not reseeded
        #expect(store.active?.name == "Custom Thing")
        #expect(store.active?.id == custom.id)
    }

    @Test func tolerantDecodeOfPreGoalSchedule() throws {
        // A schedule JSON from before dailyGoal existed decodes with the default.
        let json = Data(#"""
        {"name":"Old","steps":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-000000000003","label":"Work","minutes":25,"kind":"work"}]}
        """#.utf8)
        let decoded = try JSONDecoder().decode(Schedule.self, from: json)
        #expect(decoded.dailyGoal == 8)
        #expect(decoded.steps.count == 1)
        #expect(decoded.repeatMode == .infinite)
    }

    @Test func activeIdPersistence() {
        let defaults = makeDefaults()
        let store = ScheduleStore(defaults: defaults)
        let target = store.schedules[2]
        store.setActive(id: target.id)

        let reloaded = ScheduleStore(defaults: defaults)
        #expect(reloaded.active?.id == target.id)
    }

    @Test func deleteProtectsActiveAndLastSchedule() {
        let defaults = makeDefaults()
        let store = ScheduleStore(defaults: defaults)
        let active = store.active!.id

        // Active schedule can't be deleted.
        store.delete(id: active)
        #expect(store.schedules.contains { $0.id == active })

        // Down to one schedule: nothing deletable.
        let only = ScheduleStore(defaults: {
            let d = makeDefaults()
            let data = try! JSONEncoder().encode([Schedule(name: "Only", steps: [Step(label: "Focus", minutes: 25, kind: .work)])])
            d.set(data, forKey: "schedules.v1")
            return d
        }())
        only.delete(id: only.active!.id)
        #expect(only.schedules.count == 1)
    }
}
