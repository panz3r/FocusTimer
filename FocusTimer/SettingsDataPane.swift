import SwiftUI

/// Data pane: JSON backup export/import (restore), and the weekly
/// auto-backup options.
struct DataPane: View {
    @ObservedObject var vm: TimerViewModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Export backup…") {
                Button("Export…") { SessionExport.runExportDialog(.jsonBackup) }
            }
            Divider()
            SettingsRow("Import backup…") {
                Button("Import…") {
                    SessionExport.runImportDialog {
                        vm.refreshFromStore()
                        SyncCoordinator.shared.queueWrite()
                    }
                }
            }
            Divider()
            SettingsRow("Weekly auto-backup") {
                Toggle("", isOn: $vm.weeklyBackupEnabled).labelsHidden()
            }
            if vm.weeklyBackupEnabled {
                Divider()
                SettingsRow("Include Markdown summary") {
                    Toggle("", isOn: $vm.weeklyBackupMarkdownEnabled).labelsHidden()
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
        panel.prompt = "Use Folder"
        panel.message = "Weekly backups will be written to this folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        BackupScheduler.setFolder(url)
    }
}
