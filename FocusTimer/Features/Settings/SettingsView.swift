import SwiftUI

/// Two-pane settings: a fixed sidebar picks the section; the right pane
/// shows that section's cards. The whole view is pinned to 580x620 — the
/// hosting view height never changes, which keeps the layout-feedback-loop
/// crash (see commit "Fix Settings crash…") structurally impossible.
/// Overflow inside a pane scrolls.
///
/// Phase 2: each pane lives in its own file (SettingsXPane.swift); this
/// file is only the shell — sidebar, pane routing, and the section enum.
/// Phase 4: panes bind the SessionEngine and AppSettings directly instead
/// of the former god ViewModel.
struct SettingsView: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var settings: AppSettings

    enum Section: String, CaseIterable, Identifiable {
        case schedules    = "Schedules"
        case behavior     = "Behavior"
        case notifications = "Notifications"
        case shortcuts    = "Shortcuts"
        case social       = "Social"
        case sync         = "Sync"
        case data         = "Data"

        var id: String { rawValue }

        /// Localized display name — rawValue is a runtime value, so the
        /// catalog needs literal keys.
        var localizedName: LocalizedStringKey {
            switch self {
            case .schedules:     return "Schedules"
            case .behavior:      return "Behavior"
            case .notifications: return "Notifications"
            case .shortcuts:     return "Shortcuts"
            case .social:        return "Social"
            case .sync:          return "Sync"
            case .data:          return "Data"
            }
        }

        var icon: String {
            switch self {
            case .schedules:     return "timer"
            case .behavior:      return "gearshape"
            case .notifications: return "bell"
            case .shortcuts:     return "keyboard"
            case .social:        return "person.2"
            case .sync:          return "icloud"
            case .data:          return "externaldrive"
            }
        }
    }

    @State private var section: Section = .schedules

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
                Text(item.localizedName)
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
        Label(section.localizedName, systemImage: section.icon)
            .font(.title3.weight(.semibold))
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .schedules:     SchedulesPane(engine: engine)
        case .behavior:      BehaviorPane(engine: engine, settings: settings)
        case .notifications: NotificationsPane(settings: settings)
        case .shortcuts:     ShortcutsPane(hotkeys: HotkeyManager.shared)
        case .social:        SocialPane()
        case .sync:          SyncPane(settings: settings)
        case .data:          DataPane(engine: engine, settings: settings)
        }
    }
}
