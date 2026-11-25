import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let engine = SessionEngine.shared
    private let settings = AppSettings.shared

    // Crash diagnostics: when AppKit raises during layout (e.g. the Area 2
    // constraint-loop crash), the exception name/reason/stack land in
    // ~/Library/Logs/FocusTimer-exception.log and on stderr, instead of a
    // reason-less SIGTRAP report. Silent unless a crash happens.
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Foreground delivery: without a delegate, macOS silently drops every
        // notification this app posts while it holds focus (no banner, no
        // sound) — exactly when the user is watching the timer. Opt back in.
        UNUserNotificationCenter.current().delegate = self

        NSSetUncaughtExceptionHandler { exception in
            let report = """

            ========== UNCAUGHT EXCEPTION ==========
            time:   \(Date())
            name:   \(exception.name.rawValue)
            reason: \(exception.reason ?? "nil")
            stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            ========================================
            """
            FileHandle.standardError.write(Data(report.utf8))
            let logURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/FocusTimer-exception.log")
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data(report.utf8))
                try? handle.close()
            } else {
                try? report.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Foreground presentation: banner + sound even while the app is active.
    /// UNNotification cannot be instantiated in unit tests — verified manually.
    /// `nonisolated`: the delegate is called off-main; this body touches no
    /// MainActor state.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellable: AnyCancellable?
    private var engineCancellable: AnyCancellable?

    /// Area 4 Phase 4: the session engine's events drive the live-session
    /// mirror (SyncCoordinator) and the social stats push — the engine no
    /// longer calls into them directly.
    private func wireEngineEvents() {
        // Events are sent from the engine on the main actor; the sink runs
        // synchronously on the sending thread, so assume-isolated is sound.
        engineCancellable = SessionEngine.shared.events
            .sink { event in
                MainActor.assumeIsolated {
                switch event {
                case .mirrorChanged(let mirror):
                    SyncCoordinator.shared.updateSessionMirror(mirror)
                case .workSessionRecorded:
                    SyncCoordinator.shared.queueWrite()
                    Task { await SocialSyncService.pushTodayStats() }
                }
                }
            }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first { $0.title == "FocusTimer" }?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // Item 0: fast recovery of "today" counters after sleep / long inactivity.
    func applicationDidBecomeActive(_ notification: Notification) {
        SessionEngine.shared.resyncIfDayChanged()
        SyncCoordinator.shared.appDidBecomeActive()
    }

    // Area 3: push any pending local change before the process dies.
    func applicationWillTerminate(_ notification: Notification) {
        SyncCoordinator.shared.flushNow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
        UpdateChecker.shared.check()
        let settings = AppSettings.shared
        if settings.weeklyDigestEnabled { DigestChecker.shared.start() }
        if settings.weeklyBackupEnabled { BackupScheduler.shared.start() }
        SyncCoordinator.shared.restartIfNeeded()
        wireEngineEvents()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(SessionEngine.shared)
                .environmentObject(AppSettings.shared)
        )

        HotkeyManager.shared.onToggle = { SessionEngine.shared.toggleTimer() }
        HotkeyManager.shared.onSkip   = { SessionEngine.shared.skip() }
        if HotkeyManager.shared.hotkeysEnabled { HotkeyManager.shared.register() }

        cancellable = SessionEngine.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateButton() }
            }

        updateButton()
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        let result = NSMutableAttributedString()

        // Colored dot — only shown when session is active
        if engine.isRunning || engine.progress > 0 {
            let dotColor = sessionNSColor(opacity: engine.isRunning ? 1.0 : 0.45)
            result.append(NSAttributedString(string: "● ", attributes: [
                .foregroundColor: dotColor,
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .baselineOffset: 1.5
            ]))
        }

        // Time
        result.append(NSAttributedString(string: engine.formattedTime, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        ]))

        // Optional task label
        if settings.showTaskLabelInMenuBar, !engine.taskLabel.isEmpty {
            let raw = engine.taskLabel
            let truncated = raw.count > 20 ? String(raw.prefix(19)) + "…" : raw
            result.append(NSAttributedString(string: "  " + truncated, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11, weight: .regular)
            ]))
        }

        button.attributedTitle = result
        button.image = nil
    }

    private func sessionNSColor(opacity: Double) -> NSColor {
        let base: NSColor = switch engine.currentStep.kind {
        case .work:       .systemRed
        case .break:      .systemGreen
        case .longBreak:  .systemTeal
        }
        return base.withAlphaComponent(opacity)
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
                popoverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: String(localized: engine.isRunning ? "Pause" : "Start"),
            action: #selector(menuToggle),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let skipItem = NSMenuItem(title: String(localized: "Skip"), action: #selector(menuSkip), keyEquivalent: "")
        skipItem.target = self
        menu.addItem(skipItem)

        let resetItem = NSMenuItem(title: String(localized: "Reset"), action: #selector(menuReset), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(menuSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "Quit FocusTimer"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func menuToggle()   { engine.toggleTimer() }
    @objc private func menuSkip()     { engine.skip() }
    @objc private func menuReset()    { engine.reset() }
    @objc private func menuSettings() { SettingsWindowController.shared.open(engine: engine, settings: settings) }
}
