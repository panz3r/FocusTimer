import SwiftUI

/// Data pane: JSON backup export/import (restore), and the weekly
/// auto-backup options.
struct DataPane: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Export backup…") {
                Button("Export…") { SessionExport.runExportDialog(.jsonBackup) }
            }
            Divider()
            SettingsRow("Import backup…") {
                Button("Import…") {
                    SessionExport.runImportDialog {
                        engine.refreshFromStore()
                        SyncCoordinator.shared.queueWrite()
                    }
                }
            }
            Divider()
            SettingsRow("Weekly auto-backup") {
                Toggle("", isOn: $settings.weeklyBackupEnabled).labelsHidden()
            }
            if settings.weeklyBackupEnabled {
                Divider()
                SettingsRow("Include Markdown summary") {
                    Toggle("", isOn: $settings.weeklyBackupMarkdownEnabled).labelsHidden()
                }
                Divider()
                SettingsRow("Backup folder") {
                    Button("Choose…") { chooseBackupFolder() }
                }
            }
        }
        .settingsCard()
    }

    private func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Use Folder")
        panel.message = String(localized: "Weekly backups will be written to this folder.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        BackupScheduler.setFolder(url)
    }
}
