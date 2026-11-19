import SwiftUI

/// Session Log tab: completed sessions grouped by day, newest first.
struct StatsLogView: View {
    let range: Int
    @ObservedObject private var statsStore = StatsStore.shared

    private struct DayGroup: Identifiable {
        let date: Date
        let dateLabel: String
        let entries: [StatsStore.SessionEntry]
        var id: Date { date }
    }

    private var logGroups: [DayGroup] {
        let entries = StatsStore.shared.recentEntries(days: range)
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { date in
            DayGroup(
                date: date,
                dateLabel: dayGroupLabel(date),
                entries: (grouped[date] ?? []).sorted { $0.timestamp > $1.timestamp }
            )
        }
    }

    var body: some View {
        let groups = logGroups
        return Group {
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No sessions in this range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Complete a work session to see your log.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 48)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(groups) { group in
                            Text(group.dateLabel)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                                .padding(.bottom, 6)

                            ForEach(group.entries) { entry in
                                logRow(entry)
                                if entry.id != group.entries.last?.id {
                                    Divider().padding(.leading, 24)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func logRow(_ entry: StatsStore.SessionEntry) -> some View {
        HStack(spacing: 12) {
            Text(timeString(entry.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(entry.taskLabel.isEmpty ? "—" : entry.taskLabel)
                .font(.callout)
                .foregroundStyle(entry.taskLabel.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text("\(entry.durationMinutes)m")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .frame(height: 38)
    }

    private func dayGroupLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return fmt.string(from: date)
    }
}
