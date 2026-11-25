import Foundation

/// Restart resilience: engine state captured at every session transition
/// so a relaunch can restore a running/paused session. Deliberately
/// local-only (UserDefaults) — the iCloud mirror stays the cross-device
/// awareness channel; same-machine restore is this file's whole contract.
///
/// Two snapshot shapes, distinguished by `pausedAt`:
/// - `pausedAt != nil` — the app paused (idle-pause or a clean quit, which
///   parks the session paused). Restores frozen at `timeRemainingAtSave`.
/// - `pausedAt == nil` — the snapshot caught a running session, which only
///   happens on a crash/force-quit (`applicationWillTerminate` never ran).
///   Remaining is re-derived from the wall clock; if the step's time
///   already passed, the session drops — a resurrection can't claim
///   time that wasn't worked.
///
/// Expiry mirrors the iCloud awareness contract (`ActiveSession`): time
/// passed for running snapshots, paused for over a day otherwise.
struct SessionSnapshot: Codable, Equatable {
    let scheduleId: UUID
    let stepIndex: Int
    let cycleCount: Int
    let completedWorkSteps: Int
    let accumulatedMinutes: Int
    let isScheduleFinished: Bool
    let taskLabel: String
    let sessionId: UUID
    let startedAt: Date
    let durationSeconds: Int
    /// The engine's countdown at save time — authoritative for paused
    /// restores (the tick timer is cancelled while paused, so this is
    /// exactly what the user saw on screen).
    let timeRemainingAtSave: Int
    /// Paused/idle-paused/clean-quit stamp; nil while running.
    let pausedAt: Date?
    let savedAt: Date

    /// Remaining seconds by wall clock — how the crash path (and every
    /// other Mac, via the mirror) accounts a running session. Paused
    /// sessions are frozen at their pause moment.
    var wallClockRemaining: Int {
        let reference = pausedAt ?? Date()
        return max(0, durationSeconds - Int(reference.timeIntervalSince(startedAt)))
    }

    var isExpired: Bool {
        if let pausedAt {
            return Date().timeIntervalSince(pausedAt) > 24 * 3600
        }
        return wallClockRemaining <= 0
    }
}
