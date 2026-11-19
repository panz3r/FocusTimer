import AppKit
import UserNotifications

/// The notification sound options offered in Settings. Named sounds play
/// via NSSound at session-complete (no-op for Default/None), so the
/// notification itself carries no sound — avoiding a double-play.
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
