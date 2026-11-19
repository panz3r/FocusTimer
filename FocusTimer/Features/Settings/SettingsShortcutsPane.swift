import SwiftUI

/// Shortcuts pane: global hotkey enable + the two key recorders.
struct ShortcutsPane: View {
    @ObservedObject var hotkeys: HotkeyManager

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Global shortcuts") {
                Toggle("", isOn: $hotkeys.hotkeysEnabled).labelsHidden()
            }
            if hotkeys.hotkeysEnabled {
                Divider()
                SettingsRow("Start / Pause") {
                    KeyRecorder(
                        label: hotkeys.toggleHotkeyLabel,
                        onStartRecording: { HotkeyManager.shared.unregister() },
                        onCancel: { if hotkeys.hotkeysEnabled { HotkeyManager.shared.register() } },
                        onRecord: { code, mods, label in
                            hotkeys.updateToggleHotkey(code: code, mods: mods, label: label)
                        }
                    )
                }
                Divider()
                SettingsRow("Skip") {
                    KeyRecorder(
                        label: hotkeys.skipHotkeyLabel,
                        onStartRecording: { HotkeyManager.shared.unregister() },
                        onCancel: { if hotkeys.hotkeysEnabled { HotkeyManager.shared.register() } },
                        onRecord: { code, mods, label in
                            hotkeys.updateSkipHotkey(code: code, mods: mods, label: label)
                        }
                    )
                }
            }
        }
        .settingsCard()
    }
}
