import SwiftUI
import Charts

/// Stats window shell: header (export menu + range picker), tab bar, and
/// the three tab panes (each in its own file). `range` is shared by the
/// Overview and Patterns panes.
struct StatsView: View {
    @ObservedObject private var statsStore = StatsStore.shared
    @State private var tab: Tab = .overview
    @State private var range: Int = 28

    enum Tab: String, CaseIterable {
        case overview  = "Overview"
        case patterns  = "Patterns"
        case log       = "Session Log"
    }

    private var data: [StatsStore.DayStat] { StatsStore.shared.history(days: range) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            if tab == .overview {
                StatsOverviewView(range: range)
                    .overlay(alignment: .bottom) { Divider() }
                StatsFooterView(data: data, range: range)
            } else if tab == .patterns {
                StatsPatternsView(range: range)
            } else {
                StatsLogView(range: range)
            }
        }
        .frame(width: 500)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Stats History")
                .font(.title2.weight(.semibold))
            Spacer()
            Menu {
                Button("JSON backup…") { SessionExport.runExportDialog(.jsonBackup) }
                Button("CSV…") { SessionExport.runExportDialog(.csv) }
                Button("Markdown summary…") { SessionExport.runExportDialog(.markdown) }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("Export…")

            Picker("", selection: $range) {
                Text("1 week").tag(7)
                Text("2 weeks").tag(14)
                Text("4 weeks").tag(28)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 100)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}

/// Shared formatting helper for focus-time strings ("45m", "2h 25m").
enum StatsFormatting {
    static func hours(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// Bottom footer with aggregate stats (shown on the Overview and Patterns
/// tabs).
struct StatsFooterView: View {
    let data: [StatsStore.DayStat]
    let range: Int

    var body: some View {
        HStack(spacing: 24) {
            footerStat("Avg / active day", avgPerActiveDay)
            footerStat("Active days", "\(data.filter { $0.sessions > 0 }.count) of \(range)")
            footerStat("Total focus", StatsFormatting.hours(data.reduce(0) { $0 + $1.focusMinutes }))
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func footerStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var avgPerActiveDay: String {
        let active = data.filter { $0.sessions > 0 }
        guard !active.isEmpty else { return "—" }
        let avg = Double(active.reduce(0) { $0 + $1.sessions }) / Double(active.count)
        return String(format: "%.1f", avg)
    }
}
