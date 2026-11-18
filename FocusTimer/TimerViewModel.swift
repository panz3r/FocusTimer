import Foundation
import Combine
import CoreGraphics
import ServiceManagement

final class TimerViewModel: ObservableObject {
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

    @Published var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: "dailyGoal") }
    }
    @Published var autoAdvance: Bool {
        didSet { UserDefaults.standard.set(autoAdvance, forKey: "autoAdvance") }
    }
    @Published var showTaskLabelInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showTaskLabelInMenuBar, forKey: "showTaskLabelInMenuBar") }
    }
    @Published var hotkeysEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotkeysEnabled, forKey: "hotkeysEnabled")
            if hotkeysEnabled { HotkeyManager.shared.register() } else { HotkeyManager.shared.unregister() }
        }
    }
    @Published var notificationSound: NotificationSound {
        didSet { UserDefaults.standard.set(notificationSound.rawValue, forKey: "notificationSound") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            if launchAtLogin { try? SMAppService.mainApp.register() }
            else             { try? SMAppService.mainApp.unregister() }
        }
    }
    @Published var idleDetectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(idleDetectionEnabled, forKey: "idleDetectionEnabled")
            if idleDetectionEnabled { if isRunning { startIdleMonitor() } }
            else { stopIdleMonitor() }
        }
    }
    @Published var idlePauseThreshold: Int {
        didSet { UserDefaults.standard.set(idlePauseThreshold, forKey: "idlePauseThreshold") }
    }
    @Published var weeklyDigestEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weeklyDigestEnabled, forKey: "weeklyDigestEnabled")
            if weeklyDigestEnabled { DigestChecker.shared.start() } else { DigestChecker.shared.stop() }
        }
    }
    @Published var weeklyBackupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weeklyBackupEnabled, forKey: "weeklyBackupEnabled")
            BackupScheduler.shared.restartIfNeeded()
        }
    }
    @Published var weeklyBackupMarkdownEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weeklyBackupMarkdownEnabled, forKey: "weeklyBackupMarkdownEnabled")
        }
    }
    @Published var icloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(icloudSyncEnabled, forKey: "icloudSyncEnabled")
            SyncCoordinator.shared.restartIfNeeded()
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var toggleHotkeyLabel: String
    @Published var skipHotkeyLabel: String
    @Published var taskLabel: String {
        didSet { UserDefaults.standard.set(taskLabel, forKey: "taskLabel") }
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

        notificationsEnabled = ud.object(forKey: "notificationsEnabled") as? Bool ?? true
        let goal = ud.integer(forKey: "dailyGoal")
        dailyGoal = goal > 0 ? goal : 8
        autoAdvance = ud.object(forKey: "autoAdvance") as? Bool ?? true
        showTaskLabelInMenuBar = ud.object(forKey: "showTaskLabelInMenuBar") as? Bool ?? false
        hotkeysEnabled = ud.object(forKey: "hotkeysEnabled") as? Bool ?? true
        let soundRaw = ud.string(forKey: "notificationSound") ?? NotificationSound.systemDefault.rawValue
        notificationSound = NotificationSound(rawValue: soundRaw) ?? .systemDefault
        launchAtLogin = SMAppService.mainApp.status == .enabled
        idleDetectionEnabled = ud.object(forKey: "idleDetectionEnabled") as? Bool ?? true
        let idleThresh = ud.integer(forKey: "idlePauseThreshold")
        idlePauseThreshold = idleThresh > 0 ? idleThresh : 5
        weeklyDigestEnabled = ud.object(forKey: "weeklyDigestEnabled") as? Bool ?? true
        weeklyBackupEnabled = ud.object(forKey: "weeklyBackupEnabled") as? Bool ?? false
        weeklyBackupMarkdownEnabled = ud.object(forKey: "weeklyBackupMarkdownEnabled") as? Bool ?? false
        icloudSyncEnabled = ud.object(forKey: "icloudSyncEnabled") as? Bool ?? SyncCoordinator.iCloudDriveAvailable
        toggleHotkeyLabel = ud.string(forKey: "toggleHotkeyLabel") ?? "⌃⌥Space"
        skipHotkeyLabel   = ud.string(forKey: "skipHotkeyLabel")   ?? "⌃⌥S"
        taskLabel         = ud.string(forKey: "taskLabel")         ?? ""

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

        // Item 0: poll once a minute so the UI's "today" counters reset
        // when the date rolls over without an app restart.
        daySyncCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.resyncIfDayChanged() }
    }

    func updateToggleHotkey(code: Int, mods: Int, label: String) {
        let ud = UserDefaults.standard
        let skipCode = ud.object(forKey: "skipHotkeyCode") as? Int ?? 1
        let skipMods = ud.object(forKey: "skipHotkeyMods") as? Int ?? 6144
        guard code != skipCode || mods != skipMods else {
            if hotkeysEnabled { HotkeyManager.shared.register() }
            return
        }
        ud.set(code, forKey: "toggleHotkeyCode")
        ud.set(mods, forKey: "toggleHotkeyMods")
        ud.set(label, forKey: "toggleHotkeyLabel")
        toggleHotkeyLabel = label
        if hotkeysEnabled { HotkeyManager.shared.register() }
    }

    func updateSkipHotkey(code: Int, mods: Int, label: String) {
        let ud = UserDefaults.standard
        let toggleCode = ud.object(forKey: "toggleHotkeyCode") as? Int ?? 49
        let toggleMods = ud.object(forKey: "toggleHotkeyMods") as? Int ?? 6144
        guard code != toggleCode || mods != toggleMods else {
            if hotkeysEnabled { HotkeyManager.shared.register() }
            return
        }
        ud.set(code, forKey: "skipHotkeyCode")
        ud.set(mods, forKey: "skipHotkeyMods")
        ud.set(label, forKey: "skipHotkeyLabel")
        skipHotkeyLabel = label
        if hotkeysEnabled { HotkeyManager.shared.register() }
    }

    var progress: Double {
        guard sessionStartDuration > 0 else { return 0 }
        return Double(sessionStartDuration - timeRemaining) / Double(sessionStartDuration)
    }

    var formattedTime: String {
        String(format: "%02d:%02d", timeRemaining / 60, timeRemaining % 60)
    }

    /// Area 4: switches the active schedule. Locked decision: disallowed
    /// while a session is running (reset first). Applies the schedule's
    /// first step immediately.
    func switchSchedule(to id: UUID) {
        guard !isRunning else { return }
        guard let schedule = ScheduleStore.shared.schedule(id: id) else { return }
        currentSchedule = schedule
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
        clearSessionFromSync()
        isRunning = false
    }

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
        pushSessionToSync(paused: false)
    }

    func pause() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        stopIdleMonitor()
        pausedAtLocally = Date()
        pushSessionToSync(paused: true)
    }

    private func pauseForIdle() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        // Idle monitor stays running to detect when user returns
        pausedAtLocally = Date()
        pushSessionToSync(paused: true)
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
        clearSessionFromSync()
        restartSchedulePositions()
        isRunning = false
    }

    func skip() {
        pause()
        clearSessionFromSync()
        advance()
        if autoAdvance { start() }
    }

    /// Restarts the schedule from its first step (Item 0-style hold state
    /// after a `.count`/`.untilTotalMinutes` schedule finishes).
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
        clearSessionFromSync()

        let completedMinutes = Int(Double(sessionStartDuration) / 60.0)
        accumulatedMinutes += completedMinutes

        if notificationsEnabled {
            notificationSound.playAtSessionEnd()
            NotificationManager.shared.notify(
                stepCompleted: currentStep.kind,
                stepLabel: currentStep.label,
                taskLabel: taskLabel,
                sound: notificationSound.unSound
            )
        }

        if currentStep.kind == .work {
            completedWorkSteps += 1
            StatsStore.shared.recordSession(
                durationMinutes: completedMinutes,
                taskLabel: taskLabel,
                stepLabel: currentStep.label
            )
            // Item 0: read the post-increment count from the store instead of
            // `+= 1` on a possibly stale value.
            completedPomodoros = StatsStore.shared.todaySessions
            syncStats()
            SyncCoordinator.shared.queueWrite()
        }

        advance()
        if autoAdvance && !isScheduleFinished { start() }
    }

    private func syncStats() {
        let sessions = StatsStore.shared.todaySessions
        let minutes  = StatsStore.shared.todayFocusMinutes
        let streak   = StatsStore.shared.currentStreak
        Task {
            // Area 2: registry-based, deny-by-default. No config → NoopProvider,
            // no network call.
            let config = SocialConfig.load()
            let provider = SocialProviderRegistry.activeProvider(using: config)
            guard provider.isConfigured, config.isExplicitlyEnabled else { return }
            let stats = TodayStats(
                username: config.username ?? "",
                date: StatsStore.todayKey,
                sessions: sessions,
                focusMinutes: minutes,
                streak: streak,
                exportedAt: Date()
            )
            try? await provider.postTodayStats(stats)
        }
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

    /// Area 1: re-reads today's counters from the store after a backup
    /// import merges data in. Setting the @Published property re-renders
    /// every view bound to this view model.
    func refreshFromStore() {
        completedPomodoros = StatsStore.shared.todaySessions
    }

    // MARK: - Current-session mirror (Area 3)

    private func pushSessionToSync(paused: Bool) {
        SyncCoordinator.shared.pushCurrentSession(
            id: activeSessionId,
            type: currentStep.kind.rawValue,
            label: currentStep.label,
            startedAt: sessionStartedAt,
            durationSeconds: sessionStartDuration,
            paused: paused
        )
    }

    private func clearSessionFromSync() {
        SyncCoordinator.shared.pushCurrentSession(nil)
    }

    // MARK: - Schedule editing (Area 4, Settings pane)

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
    }

    private func finishSchedule() {
        isScheduleFinished = true
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        stopIdleMonitor()
        pausedAtLocally = nil
        timeRemaining = 0
        clearSessionFromSync()
        if notificationsEnabled {
            NotificationManager.shared.notify(scheduleCompleted: currentSchedule.name)
        }
    }
}
