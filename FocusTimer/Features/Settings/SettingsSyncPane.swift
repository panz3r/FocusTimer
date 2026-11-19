import SwiftUI

/// Sync pane: iCloud Drive toggle, last-sync state, manual sync, folder
/// access, and the privacy/unconfigured/error messaging.
struct SyncPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var coordinator = SyncCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                SettingsRow("Sync via iCloud Drive") {
                    Toggle("", isOn: $settings.icloudSyncEnabled).labelsHidden()
                }
                if settings.icloudSyncEnabled {
                    Divider()
                    SettingsRow("Last sync") {
                        Text(lastSyncText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    SettingsRow("Sync now") {
                        Button("Sync") { coordinator.syncNow() }
                    }
                    Divider()
                    SettingsRow("iCloud folder") {
                        Button("Open in Finder") {
                            NSWorkspace.shared.open(SyncCoordinator.syncFolder)
                        }
                    }
                }
            }
            .settingsCard()

            Text("Task labels are written to your iCloud Drive.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            switch coordinator.state {
            case .unconfigured:
                Text("iCloud Drive isn't available on this Mac — sign in to iCloud, enable iCloud Drive, then reopen Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .error(let message):
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
    }

    private var lastSyncText: String {
        guard let date = coordinator.lastSyncAt else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
