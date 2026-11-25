import Foundation
import Combine
import CoreGraphics
import SwiftUI

/// The live state a session mirrors to other Macs (Area 3). Built by the
/// engine on session events; SyncCoordinator attaches its own identity.
struct SessionMirror {
    let id: UUID
    let kind: Step.Kind
    let label: String
    let startedAt: Date
    let durationSeconds: Int
    let paused: Bool
}

/// Events the engine publishes; SyncCoordinator (and the social push)
/// react instead of the engine calling into them directly.
enum SessionEngineEvent {
    /// The live-session mirror changed; nil clears it.
    case mirrorChanged(SessionMirror?)
    /// A work step was completed and recorded — stats changed.
    case workSessionRecorded
}

/// Area 4 Phase 4: the session machinery, extracted from the former
/// TimerViewModel god object. Owns the schedule progression, pause/resume
/// math (including idle pausing), the Item 0 day-rollover poll, the task
/// label rule, and the live-session mirror publication via `events`.
///
/// Session-behavior knobs (autoAdvance, idle detection) live here because
/// the machinery consumes them directly; display/integration settings
/// live in AppSettings.
@MainActor
final class SessionEngine: ObservableObject {
    static let shared = SessionEngine()

    /// Session lifecycle + mirror + stats events.
    let events = PassthroughSubject<SessionEngineEvent, Never>()

    @Published var timeRemaining: Int
    @Published var sessionStartDuration: Int
    @Published var isRunning = false
    @Published var currentSchedule: Schedule {
        didSet { ScheduleStore.shared.save(currentSchedule) }
    }
    @Published var currentStep: Step
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var cycleCount = 0
    /// Completed work steps since the schedule started; drives the long-break
    /// cadence (`completedWorkSteps % insertedLongBreakEvery == 0`).
    @Published private(set) var completedWorkSteps = 0
    /// Completed step minutes since the schedule started (`untilTotalMinutes`).
    @Published private(set) var accumulatedMinutes = 0
    /// Set when a `.count`/`.untilTotalMinutes` schedule runs to completion;
    /// the timer holds at zero until reset.
    @Published private(set) var isScheduleFinished = false
    @Published var completedPomodoros = 0

    // Session-behavior knobs (persisted; consumed by the machinery below).
    @Published var autoAdvance: Bool {
        didSet { UserDefaults.standard.set(autoAdvance, forKey: UserDefaultsKeys.autoAdvance) }
    }
    @Published var idleDetectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(idleDetectionEnabled, forKey: UserDefaultsKeys.idleDetectionEnabled)
            if idleDetectionEnabled { if isRunning { startIdleMonitor() } }
            else { stopIdleMonitor() }
        }
    }
    @Published var idlePauseThreshold: Int {
        didSet { UserDefaults.standard.set(idlePauseThreshold, forKey: UserDefaultsKeys.idlePauseThreshold) }
    }
    @Published var taskLabel: String {
        didSet { UserDefaults.standard.set(taskLabel, forKey: UserDefaultsKeys.taskLabel) }
    }
    /// Restores a session parked by a clean quit as RUNNING at relaunch
    /// (instead of paused). Crash-restored sessions always resume — this
    /// knob only governs the quit-as-pause path.
    @Published var resumeOnRelaunch: Bool {
        didSet { UserDefaults.standard.set(resumeOnRelaunch, forKey: UserDefaultsKeys.resumeOnRelaunch) }
    }

    private var timerCancellable: AnyCancellable?
    private var idleMonitorCancellable: AnyCancellable?
    private var pausedDueToIdle = false

    // Item 0: day-rollover tracking. Seeded at init; compared against
    // StatsStore.todayKey on a 60-second poll so "today" counters re-sync
    // when the calendar date changes while the app is open.
    private var lastSyncedDayKey: String = StatsStore.todayKey
    private var daySyncCancellable: AnyCancellable?

    // Area 3: identity of the live session, mirrored to iCloud Drive so
    // other Macs can show what's running. sessionStartedAt shifts forward
    // by the paused gap on resume, keeping derived remaining time truthful.
    private var activeSessionId = UUID()
    private var sessionStartedAt = Date()
    private var pausedAtLocally: Date?

    init() {
        let ud = UserDefaults.standard

        autoAdvance = ud.object(forKey: UserDefaultsKeys.autoAdvance) as? Bool ?? true
        idleDetectionEnabled = ud.object(forKey: UserDefaultsKeys.idleDetectionEnabled) as? Bool ?? true
        let idleThresh = ud.integer(forKey: UserDefaultsKeys.idlePauseThreshold)
        idlePauseThreshold = idleThresh > 0 ? idleThresh : 5
        taskLabel = ud.string(forKey: UserDefaultsKeys.taskLabel) ?? ""
        resumeOnRelaunch = ud.object(forKey: UserDefaultsKeys.resumeOnRelaunch) as? Bool ?? false

        // Area 4: the active schedule (ScheduleStore bootstraps the legacy
        // Pomodoro migration on first launch).
        let active = ScheduleStore.shared.active ?? Schedule.legacyPomodoro(
            work: 25, shortBreak: 5, longBreakMinutes: 15, cadence: 4
        )
        let firstStep = active.steps.first ?? Step(
            label: Step.Kind.work.defaultLabel, minutes: 25, kind: .work
        )
        currentSchedule = active
        currentStep = firstStep
        let firstDuration = firstStep.minutes * 60
        sessionStartDuration = firstDuration
        timeRemaining = firstDuration
        completedPomodoros = StatsStore.shared.todaySessions

        // Restart resilience: bring back the session the app quit with.
        restoreSnapshot()

        // Item 0: poll once a minute so the UI's "today" counters reset
        // when the date rolls over without an app restart.
        daySyncCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.resyncIfDayChanged() }
    }

    // MARK: - Controls

    func toggleTimer() {
        isRunning ? pause() : start()
    }

    func start() {
        pausedDueToIdle = false
        if let pausedAt = pausedAtLocally {
            // Resuming: shift the start time past the paused gap so derived
            // remaining time on other Macs stays truthful.
            sessionStartedAt = sessionStartedAt.addingTimeInterval(Date().timeIntervalSince(pausedAt))
        } else {
            sessionStartedAt = Date()
            activeSessionId = UUID()
        }
        pausedAtLocally = nil
        isRunning = true
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        if idleDetectionEnabled { startIdleMonitor() }
        pushMirror(paused: false)
    }

    func pause() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        stopIdleMonitor()
        pausedAtLocally = Date()
        pushMirror(paused: true)
    }

    private func pauseForIdle() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        // Idle monitor stays running to detect when user returns
        pausedAtLocally = Date()
        pushMirror(paused: true)
    }

    private func startIdleMonitor() {
        idleMonitorCancellable?.cancel()
        idleMonitorCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkIdle() }
    }

    private func stopIdleMonitor() {
        idleMonitorCancellable?.cancel()
        idleMonitorCancellable = nil
        pausedDueToIdle = false
    }

    private func checkIdle() {
        let mouseIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let keyIdle   = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let idleSecs  = min(mouseIdle, keyIdle)

        if pausedDueToIdle {
            if idleSecs < 5.0 { start() } // user returned — auto-resume
        } else if isRunning, idleSecs >= Double(idlePauseThreshold * 60) {
            pausedDueToIdle = true
            pauseForIdle()
        }
    }

    func reset() {
        pause()
        clearMirror()
        restartSchedulePositions()
        isRunning = false
    }

    func skip() {
        pause()
        clearMirror()
        advance()
        if autoAdvance { start() }
    }

    /// Restarts the schedule from its first step (hold state after a
    /// `.count`/`.untilTotalMinutes` schedule finishes).
    private func restartSchedulePositions() {
        currentStepIndex = 0
        cycleCount = 0
        completedWorkSteps = 0
        accumulatedMinutes = 0
        isScheduleFinished = false
        pausedAtLocally = nil
        if let first = currentSchedule.steps.first {
            applyStep(first, at: 0)
        }
    }

    private func tick() {
        guard timeRemaining > 0 else {
            sessionComplete()
            return
        }
        timeRemaining -= 1
    }

    private func sessionComplete() {
        pause()
        clearMirror()

        let completedMinutes = Int(Double(sessionStartDuration) / 60.0)
        accumulatedMinutes += completedMinutes

        let settings = AppSettings.shared
        if settings.notificationsEnabled {
            settings.notificationSound.playAtSessionEnd()
            NotificationManager.shared.notify(
                stepCompleted: currentStep.kind,
                stepLabel: currentStep.label,
                taskLabel: taskLabel,
                sound: settings.notificationSound.unSound
            )
        }

        if currentStep.kind == .work {
            completedWorkSteps += 1
            StatsStore.shared.recordSession(
                durationMinutes: completedMinutes,
                taskLabel: taskLabel,
                stepLabel: currentStep.label,
                scheduleName: currentSchedule.name
            )
            // Item 0: read the post-increment count from the store instead of
            // `+= 1` on a possibly stale value.
            completedPomodoros = StatsStore.shared.todaySessions
            events.send(.workSessionRecorded)
        }

        advance()
        if autoAdvance && !isScheduleFinished { start() }
    }

    /// Area 1: re-reads today's counters from the store after a backup
    /// import merges data in. Setting the @Published property re-renders
    /// every view bound to the engine.
    func refreshFromStore() {
        completedPomodoros = StatsStore.shared.todaySessions
    }

    /// Item 0: re-syncs the "today" counters when the calendar day has
    /// rolled over while the app was open. Cheap no-op when the day is
    /// unchanged. Called from the 60-second poll and from
    /// AppDelegate.applicationDidBecomeActive (fast recovery after sleep).
    func resyncIfDayChanged() {
        let today = StatsStore.todayKey
        guard today != lastSyncedDayKey else { return }
        lastSyncedDayKey = today
        completedPomodoros = StatsStore.shared.todaySessions
    }

    // MARK: - Derived display state

    var progress: Double {
        guard sessionStartDuration > 0 else { return 0 }
        return Double(sessionStartDuration - timeRemaining) / Double(sessionStartDuration)
    }

    /// Per-schedule daily goal (Area 4 follow-up).
    var dailyGoal: Int { currentSchedule.dailyGoal }

    var formattedTime: String {
        String(format: "%02d:%02d", timeRemaining / 60, timeRemaining % 60)
    }

    // MARK: - Schedule progression (Area 4)

    /// Computes and applies the next step via the pure progression engine
    /// (Schedule.nextStep). The just-completed step's kind drives the
    /// long-break upgrade; finished `.count`/`.untilTotalMinutes` schedules
    /// hold until reset.
    private func advance() {
        guard let next = Schedule.nextStep(
            schedule: currentSchedule,
            after: currentStep,
            currentStepIndex: currentStepIndex,
            completedWorkSteps: completedWorkSteps,
            accumulatedMinutes: accumulatedMinutes,
            cycleCount: cycleCount
        ) else {
            finishSchedule()
            return
        }

        if next.wrapped { cycleCount += 1 }
        applyLabelRule(entering: next.step, schedule: currentSchedule)
        applyStep(next.step, at: next.index)
    }

    /// Locked label rule: non-work steps clear the label (remembered on the
    /// schedule); the next work step restores it.
    private func applyLabelRule(entering step: Step, schedule: Schedule) {
        if step.kind == .work {
            if taskLabel.trimmingCharacters(in: .whitespaces).isEmpty,
               let last = schedule.lastUsedLabel, !last.isEmpty {
                taskLabel = last
            }
        } else {
            let trimmed = taskLabel.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            var updated = schedule
            updated.lastUsedLabel = trimmed
            currentSchedule = updated   // persists through didSet
        }
    }

    private func applyStep(_ step: Step, at index: Int) {
        currentStepIndex = index
        currentStep = step
        pausedAtLocally = nil
        sessionStartDuration = step.minutes * 60
        timeRemaining = sessionStartDuration
        persistSnapshotIfInSession()
    }

    private func finishSchedule() {
        isScheduleFinished = true
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        stopIdleMonitor()
        pausedAtLocally = nil
        timeRemaining = 0
        clearMirror()
        let settings = AppSettings.shared
        if settings.notificationsEnabled {
            NotificationManager.shared.notify(scheduleCompleted: currentSchedule.name)
        }
    }

    // MARK: - Schedule editing (Settings pane)

    /// Area 4: switches the active schedule. Locked decision: disallowed
    /// while a session is running (reset first). Applies the schedule's
    /// first step immediately.
    func switchSchedule(to id: UUID) {
        guard !isRunning else { return }
        guard let schedule = ScheduleStore.shared.schedule(id: id) else { return }
        currentSchedule = schedule
        // Mark the new schedule active — the didSet above saves schedule
        // DATA only; without this the stored active id stays stale and the
        // selection is lost on relaunch (bootstrap restores the old id).
        ScheduleStore.shared.setActive(id: id)
        isScheduleFinished = false
        currentStepIndex = 0
        cycleCount = 0
        completedWorkSteps = 0
        accumulatedMinutes = 0
        pausedAtLocally = nil
        if let first = schedule.steps.first {
            applyLabelRule(entering: first, schedule: schedule)
            applyStep(first, at: 0)
        }
        clearMirror()
        isRunning = false
    }

    func addStepToCurrentSchedule() {
        currentSchedule.steps.append(Step(
            label: Step.Kind.work.defaultLabel,
            minutes: 25,
            kind: .work
        ))
    }

    func removeStepFromCurrentSchedule(_ id: UUID) {
        guard currentSchedule.steps.count > 1 else { return }
        currentSchedule.steps.removeAll { $0.id == id }
    }

    // MARK: - Live-session mirror (Area 3, via events)

    private func pushMirror(paused: Bool) {
        persistSnapshot()
        events.send(.mirrorChanged(SessionMirror(
            id: activeSessionId,
            kind: currentStep.kind,
            label: currentStep.label,
            startedAt: sessionStartedAt,
            durationSeconds: sessionStartDuration,
            paused: paused
        )))
    }

    private func clearMirror() {
        clearSnapshot()
        events.send(.mirrorChanged(nil))
    }

    // MARK: - Restart resilience (local snapshots)

    private static let snapshotKey = UserDefaultsKeys.sessionSnapshot

    /// Captures the full session state. Only called while a session exists
    /// (running or paused) — piggybacks on the mirror transitions, which
    /// already fire at every meaningful change.
    private func persistSnapshot() {
        let snapshot = SessionSnapshot(
            scheduleId: currentSchedule.id,
            stepIndex: currentStepIndex,
            cycleCount: cycleCount,
            completedWorkSteps: completedWorkSteps,
            accumulatedMinutes: accumulatedMinutes,
            isScheduleFinished: isScheduleFinished,
            taskLabel: taskLabel,
            sessionId: activeSessionId,
            startedAt: sessionStartedAt,
            durationSeconds: sessionStartDuration,
            timeRemainingAtSave: timeRemaining,
            pausedAt: pausedAtLocally,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
    }

    /// Between transitions the engine can be merely idle on a step (e.g. a
    /// completed step without auto-advance): nothing worth restoring.
    private func persistSnapshotIfInSession() {
        if isRunning || pausedAtLocally != nil {
            persistSnapshot()
        } else {
            clearSnapshot()
        }
    }

    private func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
    }

    /// Quit = pause: parks a running session paused (snapshot + mirror)
    /// so the relaunch restores it truthfully. Must run BEFORE
    /// SyncCoordinator.flushNow() so the paused mirror reaches iCloud.
    func prepareForTermination() {
        guard isRunning else { return }
        pause()
    }

    /// Rebuilds a session from the local snapshot at init.
    ///
    /// - Clean quit mid-step (`pausedAt != nil`): restore paused, frozen at
    ///   the saved countdown; auto-starts only when `resumeOnRelaunch` is on.
    /// - Crash mid-step (`pausedAt == nil`): restore running if still live
    ///   by wall clock — otherwise drop (can't claim unworked time).
    /// - Anything expired (paused > 24 h, shared with the awareness
    ///   contract), finished, or referencing a schedule that is not the
    ///   active one drops to a fresh idle state.
    private func restoreSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              !snapshot.isExpired,
              !snapshot.isScheduleFinished,
              let schedule = ScheduleStore.shared.schedule(id: snapshot.scheduleId),
              schedule.id == ScheduleStore.shared.active?.id,
              schedule.steps.indices.contains(snapshot.stepIndex) else {
            clearSnapshot()
            return
        }

        currentSchedule = schedule
        currentStepIndex = snapshot.stepIndex
        currentStep = schedule.steps[snapshot.stepIndex]
        cycleCount = snapshot.cycleCount
        completedWorkSteps = snapshot.completedWorkSteps
        accumulatedMinutes = snapshot.accumulatedMinutes
        taskLabel = snapshot.taskLabel
        activeSessionId = snapshot.sessionId
        sessionStartedAt = snapshot.startedAt
        sessionStartDuration = snapshot.durationSeconds

        if snapshot.pausedAt != nil {
            // Parked by a clean quit (or idle-pause): restore paused with
            // the exact countdown the user saw, then honor the toggle.
            pausedAtLocally = snapshot.pausedAt
            timeRemaining = snapshot.timeRemainingAtSave
            isRunning = false
            pushMirror(paused: true)
            if resumeOnRelaunch { start() }
        } else {
            // Crash: the wall clock decides; resume what's still live.
            pausedAtLocally = nil
            timeRemaining = snapshot.wallClockRemaining
            isRunning = false
            start()
        }
    }
}
