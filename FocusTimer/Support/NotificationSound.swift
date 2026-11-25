import AppKit
import SwiftUI
import UserNotifications

/// The notification sound options offered in Settings. Named sounds play
/// via NSSound at session-complete (no-op for Default/None), so the
/// notification itself carries no sound — avoiding a double-play.
/// "Default" is not a file but a delivery-time directive of the
/// notification subsystem, so its honest preview is a real notification:
/// the speaker routes through the permission-aware test flow.
enum NotificationSound: String, CaseIterable {
    case systemDefault = "Default"
    case bottle        = "Bottle"
    case glass         = "Glass"
    case hero          = "Hero"
    case morse         = "Morse"
    case ping          = "Ping"
    case pop           = "Pop"
    case submarine     = "Submarine"
    case tink          = "Tink"
    case none          = "None"

    /// Named sounds resolve to system assets (/System/Library/Sounds).
    var isNamed: Bool { self != .systemDefault && self != .none }

    /// Only None has nothing to preview (Default previews via a real
    /// notification; every named sound plays directly).
    var canPreview: Bool { self != .none }

    /// Speaker-button preview: named sounds play in-process; Default
    /// posts a real notification so the system default sound can be
    /// heard as it would actually arrive.
    func preview() {
        switch self {
        case .systemDefault:
            Task { await NotificationManager.shared.sendTestNotificationWithPermissionFlow() }
        case .none:
            break
        default:
            NSSound(named: NSSound.Name(rawValue))?.play()
        }
    }

    // Notification sound: named sounds play via NSSound at session-complete,
    // so the notification itself carries no sound (avoids double-play).
    // None carries nothing at all; Default defers to the system.
    var unSound: UNNotificationSound? {
        switch self {
        case .systemDefault: return .default
        case .none, .bottle, .glass, .hero, .morse, .ping, .pop, .submarine, .tink: return nil
        }
    }

    // Plays the NSSound variant at session-complete (no-op for Default/None).
    // Optional-chained: an unresolvable name is a silent no-op, not a crash.
    func playAtSessionEnd() {
        guard isNamed else { return }
        NSSound(named: NSSound.Name(rawValue))?.play()
    }
}
