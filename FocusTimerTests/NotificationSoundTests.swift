import Testing
import UserNotifications
@testable import FocusTimer

/// Safety net for the notification-sound palette: picker order, decode
/// compatibility with stored prefs, and the no-double-play sound mapping.
struct NotificationSoundTests {

    @Test func paletteCoversTheCuratedTenInPickerOrder() {
        #expect(NotificationSound.allCases == [
            .systemDefault, .bottle, .glass, .hero, .morse,
            .ping, .pop, .submarine, .tink, .none
        ])
    }

    @Test func rawValuesRoundTrip() {
        for sound in NotificationSound.allCases {
            #expect(NotificationSound(rawValue: sound.rawValue) == sound)
        }
    }

    @Test func legacyStoredValuesDecode() {
        #expect(NotificationSound(rawValue: "Glass") == .glass)
        #expect(NotificationSound(rawValue: "Ping") == .ping)
        #expect(NotificationSound(rawValue: "Default") == .systemDefault)
        #expect(NotificationSound(rawValue: "None") == NotificationSound.none)
    }

    @Test func unknownRawValueYieldsNil() {
        // Unknown stored values decode to nil; AppSettings then falls
        // back to .systemDefault.
        #expect(NotificationSound(rawValue: "Sosumi") == nil)
    }

    @Test func unSoundDefersOnlyForDefault() {
        #expect(NotificationSound.systemDefault.unSound == .default)
        for sound in NotificationSound.allCases where sound != .systemDefault {
            #expect(sound.unSound == nil, "\(sound.rawValue) must not double-play")
        }
    }

    @Test func canPreviewExcludesOnlyNone() {
        for sound in NotificationSound.allCases {
            #expect(sound.canPreview == (sound != .none))
        }
        #expect(!NotificationSound.none.canPreview)
    }

    @Test func isNamedMatchesTheNamedSet() {
        let named: Set<NotificationSound> = [
            .bottle, .glass, .hero, .morse, .ping, .pop, .submarine, .tink
        ]
        for sound in NotificationSound.allCases {
            #expect(sound.isNamed == named.contains(sound))
        }
        #expect(!NotificationSound.systemDefault.isNamed)
        #expect(!NotificationSound.none.isNamed)
    }

    @Test func playAtSessionEndIsSafeForEveryCase() {
        // Smoke: no force-unwraps or crashes; every named sound resolves
        // on this macOS build (optional-chained if one ever vanishes).
        for sound in NotificationSound.allCases {
            sound.playAtSessionEnd()
        }
    }
}
