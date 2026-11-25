import AppKit
import Foundation
import SwiftUI
import UserNotifications

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
        alert.messageText = String(localized: "Notifications are turned off")
        alert.informativeText = String(localized: "Enable them in System Settings → Notifications → FocusTimer, then try again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "OK"))
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func presentPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Notifications were not allowed")
        alert.informativeText = String(localized: "FocusTimer can't show session alerts without notification permission. Enable it in System Settings → Notifications → FocusTimer.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    /// Human-readable authorization state for the Settings pane.
    func authorizationDescription() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return String(localized: "Authorized")
        case .denied:
            return String(localized: "Denied — enable in System Settings → Notifications → FocusTimer")
        case .notDetermined:
            return String(localized: "Not requested yet — toggle Notifications to trigger the prompt")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    /// Posts an immediate notification so the pipeline can be verified
    /// without waiting for a session to complete.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Test notification")
        content.body = String(localized: "If you see this as a banner (or in Notification Center), notifications work.")
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
            content.title = String(localized: "Focus session complete!")
            switch taskLabel.trimmingCharacters(in: .whitespaces).lowercased() {
            case "🍅":
                content.body = String(localized: "Pomodoro complete! 🍅 Take a well-earned break.")
            case "coffee", "☕":
                content.body = String(localized: "Caffeine-fueled session complete ☕ — time to stretch.")
            case "42":
                content.body = String(localized: "42 minutes of deep thought. Don't panic. 🌌")
            case "debug", "debugging":
                content.body = String(localized: "Bug squashing session complete 🐛 How many did you get?")
            default:
                content.body = taskLabel.isEmpty
                    ? String(localized: "Time to take a break. Great focus session.")
                    : String(localized: "\(taskLabel) — take a well-earned break.")
            }
        case .break:
            content.title = String(localized: "\(stepLabel) over!")
            content.body = String(localized: "Ready to get back to it?")
        case .longBreak:
            content.title = String(localized: "\(stepLabel) over!")
            content.body = String(localized: "Fully recharged? Let's go.")
        }

        content.sound = sound

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
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
        content.title = String(localized: "Schedule complete")
        content.body = String(localized: "“\(name)” finished — nicely done.")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "schedule-complete-\(UUID())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendMilestone(sessions: Int, focusMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(sessions) sessions completed")
        let hours = focusMinutes / 60
        content.body = switch sessions {
        case 10:   String(localized: "A solid start — keep the habit going.")
        case 50:   String(localized: "50 down. You're building something real.")
        case 100:  hours > 0
                 ? String(localized: "That's \(hours)+ hours of deep work. Keep it up.")
                 : String(localized: "A major milestone — keep it up.")
        case 500:  hours > 0
                 ? String(localized: "\(hours) hours focused. Serious dedication.")
                 : String(localized: "Serious dedication.")
        case 1000: hours > 0
                 ? String(localized: "\(hours) hours of deep work. Elite level.")
                 : String(localized: "Elite level.")
        default:   String(localized: "Keep it up!")
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
        content.title = String(localized: "Auto-backup failed")
        content.body = String(localized: "\(message) Auto-backup has been turned off — re-enable it in Settings.")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "backup-failed-\(UUID())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendWeeklyDigest(sessions: Int, minutes: Int, streak: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Weekly focus summary")
        if sessions == 0 {
            content.body = String(localized: "No sessions this week — ready to start fresh?")
        } else {
            var parts: [String] = [String(localized: "\(sessions) session(s)")]
            if minutes >= 60 {
                let h = minutes / 60, m = minutes % 60
                parts.append(m == 0
                    ? String(localized: "\(h)h")
                    : String(localized: "\(h)h \(m)m"))
            } else if minutes > 0 {
                parts.append(String(localized: "\(minutes)m"))
            }
            if streak > 1 { parts.append(String(localized: "\(streak)-day streak")) }
            content.body = parts.joined(separator: " · ")
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "weekly-digest-\(UUID())", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Session/schedule notifications are gated on the Notifications toggle.
    private func notificationsGate() -> Bool {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.notificationsEnabled) as? Bool ?? true
    }
}
