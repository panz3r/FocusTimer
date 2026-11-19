import SwiftUI

/// Notifications pane: master toggle, weekly digest, sound, and the test
/// notification button (with its permission flow).
struct NotificationsPane: View {
    @ObservedObject var vm: TimerViewModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Notifications") {
                Toggle("", isOn: $vm.notificationsEnabled)
                    .labelsHidden()
                    .onChange(of: vm.notificationsEnabled) { _, enabled in
                        if enabled { NotificationManager.shared.requestPermission() }
                    }
            }
            if vm.notificationsEnabled {
                Divider()
                SettingsRow("Weekly digest") {
                    Toggle("", isOn: $vm.weeklyDigestEnabled).labelsHidden()
                }
                Divider()
                SettingsRow("Sound") {
                    HStack(spacing: 6) {
                        Button { vm.notificationSound.preview() } label: {
                            Image(systemName: "speaker.wave.2")
                                .foregroundStyle(vm.notificationSound.canPreview ? .secondary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.notificationSound.canPreview)

                        Picker("", selection: $vm.notificationSound) {
                            ForEach(NotificationSound.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }
                Divider()
                SettingsRow("Test notification") {
                    Button("Send…") {
                        Task { await NotificationManager.shared.sendTestNotificationWithPermissionFlow() }
                    }
                }
            }
        }
        .settingsCard()
    }
}
