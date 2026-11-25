import SwiftUI

/// Notifications pane: master toggle, weekly digest, sound, and the test
/// notification button (with its permission flow).
struct NotificationsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Notifications") {
                Toggle("", isOn: $settings.notificationsEnabled)
                    .labelsHidden()
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled { NotificationManager.shared.requestPermission() }
                    }
            }
            if settings.notificationsEnabled {
                Divider()
                SettingsRow("Weekly digest") {
                    Toggle("", isOn: $settings.weeklyDigestEnabled).labelsHidden()
                }
                Divider()
                SettingsRow("Sound") {
                    HStack(spacing: 6) {
                        Button { settings.notificationSound.preview() } label: {
                            Image(systemName: "speaker.wave.2")
                                .foregroundStyle(settings.notificationSound.canPreview ? .secondary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.notificationSound.canPreview)

                        Picker("", selection: $settings.notificationSound) {
                            ForEach(NotificationSound.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100) // fits "Submarine", the longest name
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
