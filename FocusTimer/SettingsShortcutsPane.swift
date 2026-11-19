import SwiftUI

/// Shortcuts pane: global hotkey enable + the two key recorders.
struct ShortcutsPane: View {
    @ObservedObject var vm: TimerViewModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Global shortcuts") {
                Toggle("", isOn: $vm.hotkeysEnabled).labelsHidden()
            }
            if vm.hotkeysEnabled {
                Divider()
                SettingsRow("Start / Pause") {
                    KeyRecorder(
                        label: vm.toggleHotkeyLabel,
                        onStartRecording: { HotkeyManager.shared.unregister() },
                        onCancel: { if vm.hotkeysEnabled { HotkeyManager.shared.register() } },
                        onRecord: { code, mods, label in
                            vm.updateToggleHotkey(code: code, mods: mods, label: label)
                        }
                    )
                }
                Divider()
                SettingsRow("Skip") {
                    KeyRecorder(
                        label: vm.skipHotkeyLabel,
                        onStartRecording: { HotkeyManager.shared.unregister() },
                        onCancel: { if vm.hotkeysEnabled { HotkeyManager.shared.register() } },
                        onRecord: { code, mods, label in
                            vm.updateSkipHotkey(code: code, mods: mods, label: label)
                        }
                    )
                }
            }
        }
        .settingsCard()
    }
}
