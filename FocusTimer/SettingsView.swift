import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: TimerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

            sectionLabel("Durations", icon: "clock")

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

            sectionLabel("Behavior", icon: "gearshape")

            card {
                settingRow("Launch at Login") {
                    Toggle("", isOn: $vm.launchAtLogin).labelsHidden()
                }
                Divider()
                settingRow("Sessions before long break") {
                    Stepper("\(vm.sessionsBeforeLongBreak)", value: $vm.sessionsBeforeLongBreak, in: 2...8)
                }
                Divider()
                settingRow("Daily goal") {
                    Stepper("\(vm.dailyGoal) sessions", value: $vm.dailyGoal, in: 1...20)
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
                Divider()
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
                }
            }
            sectionLabel("Shortcuts", icon: "keyboard")

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

            sectionLabel("Data", icon: "externaldrive")

            card {
                settingRow("Export backup…") {
                    Button("Export…") { SessionExport.runExportDialog(.jsonBackup) }
                }
                Divider()
                settingRow("Import backup…") {
                    Button("Import…") {
                        SessionExport.runImportDialog { vm.refreshFromStore() }
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

            sectionLabel("Social", icon: "person.2")

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
                            .frame(width: 130)
                    }
                    Divider()
                    settingRow("Anon key") {
                        SecureField("sb_publishable_…", text: anonKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                    }
                }
                if socialProvider.wrappedValue == .webhook {
                    Divider()
                    settingRow("Webhook URL") {
                        TextField("https://…", text: webhookURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                    }
                }
                if socialProvider.wrappedValue != .none {
                    Divider()
                    settingRow("Bearer token") {
                        SecureField("optional", text: bearerToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                    }
                    Divider()
                    settingRow("Username") {
                        TextField("you", text: socialUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
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
                    .padding(.leading, 2)
            }

            Divider()

            HStack {
                Text("Version")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(16)
        .frame(width: 320)
        }
        // Area 2 crash fix: a fixed height pins the hosting view to the
        // window, so SwiftUI content changes can't drive the window height
        // back and forth (that layout feedback loop threw "more Update
        // Constraints in Window passes than there are views" once the
        // Social section made the content tall). Overflow scrolls.
        .frame(height: 620)
    }

    // MARK: - Subviews

    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

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

    @State private var socialConfig = SocialConfig.load()

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
