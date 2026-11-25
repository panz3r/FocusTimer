import Testing
import Foundation
@testable import FocusTimer

/// Restart resilience: the snapshot's codec and its expiry/remaining
/// rules, which mirror the iCloud awareness contract (ActiveSession).
/// Engine wiring is smoke-verified (singletons + real timers).
@Suite("Session Snapshot")
struct SessionSnapshotTests {

    private func makeSnapshot(
        pausedAt: Date? = nil,
        startedAgo: TimeInterval = 0,
        duration: Int = 1500,
        savedAgo: TimeInterval = 0,
        now: Date = Date()
    ) -> SessionSnapshot {
        SessionSnapshot(
            scheduleId: UUID(),
            stepIndex: 0,
            cycleCount: 0,
            completedWorkSteps: 1,
            accumulatedMinutes: 25,
            isScheduleFinished: false,
            taskLabel: "writing",
            sessionId: UUID(),
            startedAt: now.addingTimeInterval(-startedAgo),
            durationSeconds: duration,
            timeRemainingAtSave: max(0, duration - Int(startedAgo)),
            pausedAt: pausedAt,
            savedAt: now.addingTimeInterval(-savedAgo)
        )
    }

    @Test func codecRoundTrip() throws {
        let snapshot = makeSnapshot(pausedAt: Date().addingTimeInterval(-120))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func pausedSnapshotFreezesRemaining() {
        // Paused 10 minutes into a 25-minute step: remaining is frozen at
        // the pause moment (the timer was cancelled), so it stays 15:00
        // no matter how long the pause lasts.
        let now = Date()
        let snapshot = makeSnapshot(
            pausedAt: now,
            startedAgo: 600,
            duration: 1500,
            now: now
        )
        #expect(snapshot.wallClockRemaining == 900)
        #expect(!snapshot.isExpired)              // well within 24 h
    }

    @Test func pausedSnapshotExpiresAfter24h() {
        let now = Date()
        let snapshot = makeSnapshot(
            pausedAt: now.addingTimeInterval(-25 * 3600),
            startedAgo: 600,
            now: now
        )
        #expect(snapshot.isExpired)
    }

    @Test func runningSnapshotDerivesFromWallClock() {
        // Crash path: no pausedAt — remaining is what the clock says,
        // matching how every other Mac accounts the session.
        let now = Date()
        let snapshot = makeSnapshot(startedAgo: 600, duration: 1500, now: now)
        #expect(snapshot.wallClockRemaining == 900)
        #expect(!snapshot.isExpired)
    }

    @Test func runningSnapshotExpiresWhenTimePassed() {
        let now = Date()
        let snapshot = makeSnapshot(startedAgo: 1600, duration: 1500, now: now)
        #expect(snapshot.wallClockRemaining == 0)
        #expect(snapshot.isExpired)               // can't claim unworked time
    }

    @Test func garbageDoesNotDecode() {
        // Corrupt/truncated snapshots must fail decoding so the restore
        // path treats them as absent, never as a crash.
        #expect((try? JSONDecoder().decode(SessionSnapshot.self, from: Data("junk".utf8))) == nil)
    }
}
