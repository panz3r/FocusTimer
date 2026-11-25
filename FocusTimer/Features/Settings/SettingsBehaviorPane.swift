import SwiftUI

/// Behavior pane: app-level toggles (launch/login, auto-advance, menu-bar
/// label, idle pausing).
struct BehaviorPane: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Launch at Login") {
                Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
            }
            Divider()
            SettingsRow("Auto-advance sessions") {
                Toggle("", isOn: $engine.autoAdvance).labelsHidden()
            }
            Divider()
            SettingsRow("Auto-resume after relaunch") {
                Toggle("", isOn: $engine.resumeOnRelaunch).labelsHidden()
            }
            Divider()
            SettingsRow("Show label in menu bar") {
                Toggle("", isOn: $settings.showTaskLabelInMenuBar).labelsHidden()
            }
            Divider()
            SettingsRow("Pause when idle") {
                Toggle("", isOn: $engine.idleDetectionEnabled).labelsHidden()
            }
            if engine.idleDetectionEnabled {
                Divider()
                SettingsRow("Idle threshold") {
                    Stepper("\(engine.idlePauseThreshold) min", value: $engine.idlePauseThreshold, in: 2...30)
                }
            }
        }
        .settingsCard()
    }
}
