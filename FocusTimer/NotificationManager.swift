import AppKit
import Foundation
import UserNotifications

enum NotificationSound: String, CaseIterable {
    case systemDefault = "Default"
    case glass         = "Glass"
    case ping          = "Ping"
    case none          = "None"

    // Used for the preview speaker button in Settings (only Glass/Ping support preview).
    func preview() {
        switch self {
        case .glass: NSSound(named: NSSound.Name("Glass"))?.play()
        case .ping:  NSSound(named: NSSound.Name("Ping"))?.play()
        case .systemDefault, .none: break
        }
    }

    var canPreview: Bool {
        self == .glass || self == .ping
    }

    // Notification sound: named sounds play via NSSound at session-complete,
    // so the notification itself carries no sound (avoids double-play).
    var unSound: UNNotificationSound? {
        switch self {
        case .systemDefault: return .default
        case .glass, .ping, .none: return nil
        }
    }

    // Plays the NSSound variant at session-complete (no-op for Default/None).
    func playAtSessionEnd() {
        switch self {
        case .glass: NSSound(named: NSSound.Name("Glass"))?.play()
        case .ping:  NSSound(named: NSSound.Name("Ping"))?.play()
        case .systemDefault, .none: break
        }
    }
}

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// "Send…" pipeline: sends a test notification when possible, and when
    /// permissions aren't set correctly presents an information popup
    /// instead (requesting the system prompt if never asked, or pointing at
    /// System Settings if turned off).
    @MainActor
    func sendTestNotificationWithPermissionFlow() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if granted {
                sendTestNotification()
            } else {
                presentPermissionDeniedAlert()
            }
        case .denied:
            presentNotificationsOffAlert()
        default:
            sendTestNotification()
        }
    }

    @MainActor
    private func presentNotificationsOffAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications are turned off"
        alert.informativeText = "Enable them in System Settings → Notifications → FocusTimer, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func presentPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications were not allowed"
        alert.informativeText = "FocusTimer can't show session alerts without notification permission. Enable it in System Settings → Notifications → FocusTimer."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Human-readable authorization state for the Settings pane.
    func authorizationDescription() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Authorized"
        case .denied:
            return "Denied — enable in System Settings → Notifications → FocusTimer"
        case .notDetermined:
            return "Not requested yet — toggle Notifications to trigger the prompt"
        @unknown default:
            return "Unknown"
        }
    }

    /// Posts an immediate notification so the pipeline can be verified
    /// without waiting for a session to complete.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test notification"
        content.body = "If you see this as a banner (or in Notification Center), notifications work."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "test-\(UUID())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Area 4: per-step completion notice. The legacy per-kind copy
    /// (including the task-label easter eggs) is preserved.
    func notify(stepCompleted kind: Step.Kind, stepLabel: String,
                taskLabel: String, sound: UNNotificationSound?) {
        let content = UNMutableNotificationContent()

        switch kind {
        case .work:
            content.title = "Focus session complete!"
            switch taskLabel.trimmingCharacters(in: .whitespaces).lowercased() {
            case "🍅":
                content.body = "Pomodoro complete! 🍅 Take a well-earned break."
            case "coffee", "☕":
                content.body = "Caffeine-fueled session complete ☕ — time to stretch."
            case "42":
                content.body = "42 minutes of deep thought. Don't panic. 🌌"
            case "debug", "debugging":
                content.body = "Bug squashing session complete 🐛 How many did you get?"
            default:
                content.body = taskLabel.isEmpty
                    ? "Time to take a break. Great focus session."
                    : "\(taskLabel) — take a well-earned break."
            }
        case .break:
            content.title = "\(stepLabel) over!"
            content.body = "Ready to get back to it?"
        case .longBreak:
            content.title = "\(stepLabel) over!"
            content.body = "Fully recharged? Let\u{2019}s go."
        }

        content.sound = sound

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendMilestone(sessions: Int, focusMinutes: Int) {
        let content = UNMutableNotificationContent()
        let formatted = sessions >= 1000
            ? sessions.formatted(.number)
            : "\(sessions)"
        content.title = "\(formatted) sessions completed"
        let hours = focusMinutes / 60
        content.body = switch sessions {
        case 10:   "A solid start — keep the habit going."
        case 50:   "50 down. You're building something real."
        case 100:  hours > 0 ? "That's \(hours)+ hours of deep work. Keep it up." : "A major milestone — keep it up."
        case 500:  hours > 0 ? "\(hours) hours focused. Serious dedication." : "Serious dedication."
        case 1000: hours > 0 ? "\(hours) hours of deep work. Elite level." : "Elite level."
        default:   "Keep it up!"
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "milestone-\(sessions)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Area 1: the weekly auto-backup failed (usually a vanished folder).
    /// Shown once before auto-backup turns itself off.
    func sendBackupFailed(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Auto-backup failed"
        content.body = "\(message) Auto-backup has been turned off — re-enable it in Settings."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "backup-failed-\(UUID())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Area 4: fired once when a `.count`/`.untilTotalMinutes` schedule
    /// runs to completion.
    func notify(scheduleCompleted name: String) {
        guard notificationsGate() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Schedule complete"
        content.body = "“\(name)” finished — nicely done."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "schedule-complete-\(UUID())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Session/schedule notifications are gated on the Notifications toggle.
    private func notificationsGate() -> Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    func sendWeeklyDigest(sessions: Int, minutes: Int, streak: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Weekly focus summary"
        if sessions == 0 {
            content.body = "No sessions this week — ready to start fresh?"
        } else {
            var parts: [String] = ["\(sessions) session\(sessions == 1 ? "" : "s")"]
            if minutes >= 60 {
                let h = minutes / 60, m = minutes % 60
                parts.append(m == 0 ? "\(h)h" : "\(h)h \(m)m")
            } else if minutes > 0 {
                parts.append("\(minutes)m")
            }
            if streak > 1 { parts.append("\(streak)-day streak") }
            content.body = parts.joined(separator: " · ")
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "weekly-digest-\(UUID())", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
