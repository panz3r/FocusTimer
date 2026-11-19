import AppKit
import SwiftUI

/// Two-pane settings (Area 2 follow-up): a fixed sidebar picks the section;
/// the right pane shows that section's cards. The whole view is pinned to
/// 560x620 — the hosting view height never changes, which keeps the
/// layout-feedback-loop crash (see commit "Fix Settings crash…")
/// structurally impossible. Overflow inside a pane scrolls.
struct SettingsView: View {
    @ObservedObject var vm: TimerViewModel
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared

    enum Section: String, CaseIterable, Identifiable {
        case timer        = "Timer"
        case behavior     = "Behavior"
        case notifications = "Notifications"
        case shortcuts    = "Shortcuts"
        case social       = "Social"
        case sync         = "Sync"
        case data         = "Data"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .timer:         return "clock"
            case .behavior:      return "gearshape"
            case .notifications: return "bell"
            case .shortcuts:     return "keyboard"
            case .social:        return "person.2"
            case .sync:          return "icloud"
            case .data:          return "externaldrive"
            }
        }
    }

    @State private var section: Section = .timer
    @State private var socialConfig = SocialConfig.load()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    paneHeader
                    content
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 580, height: 620)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { item in
                sidebarItem(item)
            }
            Spacer()
            Divider()
            Text("Version \(appVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
        .padding(10)
        .frame(width: 162)
    }

    private func sidebarItem(_ item: Section) -> some View {
        Button {
            section = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .frame(width: 16)
                Text(item.rawValue)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(section == item ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(section == item ? Color.accentColor.opacity(0.18) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: - Content pane

    private var paneHeader: some View {
        Label(section.rawValue, systemImage: section.icon)
            .font(.title3.weight(.semibold))
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .timer:         timerPane
        case .behavior:      behaviorPane
        case .notifications: notificationsPane
        case .shortcuts:     shortcutsPane
        case .data:          dataPane
        case .social:        socialPane
        case .sync:          syncPane
        }
    }

    private var timerPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                settingRow("Work session") {
                    Stepper("\(vm.workDuration) min", value: $vm.workDuration, in: 1...90)
                }
                Divider()
                settingRow("Short break") {
                    Stepper("\(vm.shortBreakDuration) min", value: $vm.shortBreakDuration, in: 1...30)
                }
                Divider()
                settingRow("Long break") {
                    Stepper("\(vm.longBreakDuration) min", value: $vm.longBreakDuration, in: 5...60)
                }
            }

            card {
                settingRow("Sessions before long break") {
                    Stepper("\(vm.sessionsBeforeLongBreak)", value: $vm.sessionsBeforeLongBreak, in: 2...8)
                }
                Divider()
                settingRow("Daily goal") {
                    Stepper("\(vm.dailyGoal) sessions", value: $vm.dailyGoal, in: 1...20)
                }
            }
        }
    }

    private var behaviorPane: some View {
        card {
            settingRow("Launch at Login") {
                Toggle("", isOn: $vm.launchAtLogin).labelsHidden()
            }
            Divider()
            settingRow("Auto-advance sessions") {
                Toggle("", isOn: $vm.autoAdvance).labelsHidden()
            }
            Divider()
            settingRow("Show label in menu bar") {
                Toggle("", isOn: $vm.showTaskLabelInMenuBar).labelsHidden()
            }
            Divider()
            settingRow("Pause when idle") {
                Toggle("", isOn: $vm.idleDetectionEnabled).labelsHidden()
            }
            if vm.idleDetectionEnabled {
                Divider()
                settingRow("Idle threshold") {
                    Stepper("\(vm.idlePauseThreshold) min", value: $vm.idlePauseThreshold, in: 2...30)
                }
            }
        }
    }

    private var notificationsPane: some View {
        card {
            settingRow("Notifications") {
                Toggle("", isOn: $vm.notificationsEnabled)
                    .labelsHidden()
                    .onChange(of: vm.notificationsEnabled) { enabled in
                        if enabled { NotificationManager.shared.requestPermission() }
                    }
            }
            if vm.notificationsEnabled {
                Divider()
                settingRow("Weekly digest") {
                    Toggle("", isOn: $vm.weeklyDigestEnabled).labelsHidden()
                }
                Divider()
                settingRow("Sound") {
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
                settingRow("Test notification") {
                    Button("Send…") {
                        Task { await NotificationManager.shared.sendTestNotificationWithPermissionFlow() }
                    }
                }
            }
        }
    }

    private var shortcutsPane: some View {
        card {
            settingRow("Global shortcuts") {
                Toggle("", isOn: $vm.hotkeysEnabled).labelsHidden()
            }
            if vm.hotkeysEnabled {
                Divider()
                settingRow("Start / Pause") {
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
                settingRow("Skip") {
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
    }

    private var dataPane: some View {
        card {
            settingRow("Export backup…") {
                Button("Export…") { SessionExport.runExportDialog(.jsonBackup) }
            }
            Divider()
            settingRow("Import backup…") {
                Button("Import…") {
                    SessionExport.runImportDialog {
                        vm.refreshFromStore()
                        SyncCoordinator.shared.queueWrite()
                    }
                }
            }
            Divider()
            settingRow("Weekly auto-backup") {
                Toggle("", isOn: $vm.weeklyBackupEnabled).labelsHidden()
            }
            if vm.weeklyBackupEnabled {
                Divider()
                settingRow("Include Markdown summary") {
                    Toggle("", isOn: $vm.weeklyBackupMarkdownEnabled).labelsHidden()
                }
                Divider()
                settingRow("Backup folder") {
                    Button("Choose…") { chooseBackupFolder() }
                }
            }
        }
    }

    private var syncPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                settingRow("Sync via iCloud Drive") {
                    Toggle("", isOn: $vm.icloudSyncEnabled).labelsHidden()
                }
                if vm.icloudSyncEnabled {
                    Divider()
                    settingRow("Last sync") {
                        Text(lastSyncText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    settingRow("Sync now") {
                        Button("Sync") { syncCoordinator.syncNow() }
                    }
                    Divider()
                    settingRow("iCloud folder") {
                        Button("Open in Finder") {
                            NSWorkspace.shared.open(SyncCoordinator.syncFolder)
                        }
                    }
                }
            }

            Text("Task labels are written to your iCloud Drive.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            switch syncCoordinator.state {
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
        guard let date = syncCoordinator.lastSyncAt else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var socialPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                settingRow("Provider") {
                    Picker("", selection: socialProvider) {
                        Text("None").tag(SocialConfig.Provider.none)
                        Text("Supabase").tag(SocialConfig.Provider.supabase)
                        Text("Webhook").tag(SocialConfig.Provider.webhook)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                if socialProvider.wrappedValue == .supabase {
                    Divider()
                    settingRow("Supabase URL") {
                        TextField("https://…supabase.co", text: supabaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    Divider()
                    settingRow("Anon key") {
                        SecureField("sb_publishable_…", text: anonKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }
                if socialProvider.wrappedValue == .webhook {
                    Divider()
                    settingRow("Webhook URL") {
                        TextField("https://…", text: webhookURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }
                if socialProvider.wrappedValue != .none {
                    Divider()
                    settingRow("Bearer token") {
                        SecureField("optional", text: bearerToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    Divider()
                    settingRow("Username") {
                        TextField("you", text: socialUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                            .autocorrectionDisabled()
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Friends (one per line, max 25)")
                            .font(.callout)
                        TextEditor(text: friendsText)
                            .font(.caption)
                            .frame(height: 56)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }

            if socialProvider.wrappedValue != .none {
                Text("Friend list is stored locally — make sure these usernames exist on the selected backend.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Subviews

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func settingRow<T: View>(_ label: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
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

    // MARK: Social (Area 2)

    private var socialProvider: Binding<SocialConfig.Provider> {
        Binding(
            get: { socialConfig.provider },
            set: { socialConfig.provider = $0; saveSocialConfig() }
        )
    }

    private var supabaseURL: Binding<String> {
        Binding(
            get: { socialConfig.baseURL?.absoluteString ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                socialConfig.baseURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                saveSocialConfig()
            }
        )
    }

    private var anonKey: Binding<String> {
        Binding(
            get: { socialConfig.anonKey ?? "" },
            set: { socialConfig.anonKey = $0.isEmpty ? nil : $0; saveSocialConfig() }
        )
    }

    private var webhookURL: Binding<String> {
        Binding(
            get: { socialConfig.baseURL?.absoluteString ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                socialConfig.baseURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                saveSocialConfig()
            }
        )
    }

    private var bearerToken: Binding<String> {
        Binding(
            get: { socialConfig.bearerToken ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                socialConfig.bearerToken = trimmed.isEmpty ? nil : trimmed
                saveSocialConfig()
            }
        )
    }

    private var socialUsername: Binding<String> {
        Binding(
            get: { socialConfig.username ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces).lowercased()
                socialConfig.username = trimmed.isEmpty ? nil : trimmed
                saveSocialConfig()
            }
        )
    }

    private var friendsText: Binding<String> {
        Binding(
            get: { socialConfig.usernames.joined(separator: "\n") },
            set: {
                let names = $0
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                socialConfig.usernames = Array(names.prefix(25))
                saveSocialConfig()
            }
        )
    }

    private func saveSocialConfig() {
        socialConfig.save()
    }
}

private struct KeyRecorder: View {
    let label: String
    let onStartRecording: () -> Void
    let onCancel: () -> Void
    let onRecord: (Int, Int, String) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    private static var isAnyRecording = false

    var body: some View {
        Button { toggleRecording() } label: {
            Text(isRecording ? "Press keys…" : label)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color(NSColor.controlColor))
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isRecording ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording(cancelled: true) }
    }

    private func toggleRecording() {
        isRecording ? stopRecording(cancelled: true) : startRecording()
    }

    private func startRecording() {
        guard !KeyRecorder.isAnyRecording else { return }
        isRecording = true
        KeyRecorder.isAnyRecording = true
        onStartRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.isRecording else { return event }
            if event.keyCode == 53 { // Escape cancels
                self.stopRecording(cancelled: true)
                return nil
            }
            let mods = self.carbonMods(from: event.modifierFlags)
            guard mods != 0 else { return nil }
            let display = self.modifierSymbols(mods) + self.keyLabel(for: event)
            self.onRecord(Int(event.keyCode), mods, display)
            self.stopRecording(cancelled: false)
            return nil
        }
    }

    private func stopRecording(cancelled: Bool) {
        guard isRecording else { return }
        isRecording = false
        KeyRecorder.isAnyRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if cancelled { onCancel() }
    }

    private func carbonMods(from flags: NSEvent.ModifierFlags) -> Int {
        var c = 0
        if flags.contains(.control) { c |= 4096 }
        if flags.contains(.option)  { c |= 2048 }
        if flags.contains(.command) { c |= 256  }
        if flags.contains(.shift)   { c |= 512  }
        return c
    }

    private func modifierSymbols(_ mods: Int) -> String {
        var s = ""
        if mods & 4096 != 0 { s += "⌃" }
        if mods & 2048 != 0 { s += "⌥" }
        if mods & 256  != 0 { s += "⌘" }
        if mods & 512  != 0 { s += "⇧" }
        return s
    }

    private func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:  return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
