import SwiftUI

/// Behavior pane: app-level toggles (launch/login, auto-advance, menu-bar
/// label, idle pausing).
struct BehaviorPane: View {
    @ObservedObject var vm: TimerViewModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Launch at Login") {
                Toggle("", isOn: $vm.launchAtLogin).labelsHidden()
            }
            Divider()
            SettingsRow("Auto-advance sessions") {
                Toggle("", isOn: $vm.autoAdvance).labelsHidden()
            }
            Divider()
            SettingsRow("Show label in menu bar") {
                Toggle("", isOn: $vm.showTaskLabelInMenuBar).labelsHidden()
            }
            Divider()
            SettingsRow("Pause when idle") {
                Toggle("", isOn: $vm.idleDetectionEnabled).labelsHidden()
            }
            if vm.idleDetectionEnabled {
                Divider()
                SettingsRow("Idle threshold") {
                    Stepper("\(vm.idlePauseThreshold) min", value: $vm.idlePauseThreshold, in: 2...30)
                }
            }
        }
        .settingsCard()
    }
}
