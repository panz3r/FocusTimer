import SwiftUI
import Charts

/// Overview tab: summary cards, the 16-week activity heatmap, the metric
/// picker (sessions vs focus time), and the daily bar chart.
struct StatsOverviewView: View {
    let range: Int
    @ObservedObject private var statsStore = StatsStore.shared
    @State private var metric: Metric = .sessions

    enum Metric: String, CaseIterable {
        case sessions  = "Sessions"
        case focusTime = "Focus Time"

        var localizedName: LocalizedStringKey {
            switch self {
            case .sessions:  return "Sessions"
            case .focusTime: return "Focus Time"
            }
        }
    }

    private var data: [StatsStore.DayStat] { StatsStore.shared.history(days: range) }

    var body: some View {
        VStack(spacing: 0) {
            summaryRow
            Divider()
            VStack(spacing: 20) {
                heatmapSection
                metricPicker
                barChart
            }
            .padding(24)
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            summaryCard(
                value: "\(data.reduce(0) { $0 + $1.sessions })",
                label: "sessions",
                icon: "timer"
            )
            Divider().frame(height: 44)
            summaryCard(
                value: StatsFormatting.hours(data.reduce(0) { $0 + $1.focusMinutes }),
                label: "focus time",
                icon: "clock"
            )
            Divider().frame(height: 44)
            summaryCard(
                value: "\(StatsStore.shared.currentStreak)",
                label: "day streak",
                icon: "flame"
            )
            Divider().frame(height: 44)
            summaryCard(
                value: bestDay,
                label: "best day",
                icon: "star"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func summaryCard(value: String, label: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var bestDay: String {
        let best = data.max(by: { $0.sessions < $1.sessions })
        guard let b = best, b.sessions > 0 else { return "—" }
        return "\(b.sessions)"
    }

    // MARK: - Heatmap

    private let heatmapWeeks = 16
    private let cellSize: CGFloat = 24
    private let cellGap: CGFloat = 3

    private var heatmapData: [[StatsStore.DayStat?]] { buildHeatmap(weeks: heatmapWeeks) }
    private var heatmapLabels: [String?] { monthLabels(for: heatmapData) }

    /// Locale-aware day-of-week initials, Monday-first (matches the grid
    /// column order). English renders M/_/W/_/F — identical to the previous
    /// hardcoded array, but follows the system language.
    private var dayOfWeekInitials: [String] {
        var symbols = Calendar.current.veryShortWeekdaySymbols   // Sun-first
        symbols.append(symbols.removeFirst())                    // rotate Sun to end
        return symbols
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Month labels row
            HStack(alignment: .top, spacing: cellGap) {
                Color.clear.frame(width: 18)
                ForEach(0..<heatmapData.count, id: \.self) { w in
                    Color.clear
                        .frame(width: cellSize, height: 12)
                        .overlay(alignment: .leading) {
                            if let label = heatmapLabels[w] {
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                }
            }

            // Grid
            HStack(alignment: .top, spacing: cellGap) {
                // Day-of-week labels
                VStack(alignment: .trailing, spacing: cellGap) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(verbatim: dayOfWeekInitials[d])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: cellSize)
                    }
                }

                // Week columns
                ForEach(0..<heatmapData.count, id: \.self) { w in
                    VStack(spacing: cellGap) {
                        ForEach(0..<7, id: \.self) { d in
                            let stat = heatmapData[w][d]
                            RoundedRectangle(cornerRadius: 4)
                                .fill(cellColor(for: stat))
                                .frame(width: cellSize, height: cellSize)
                                .help(cellTooltip(stat))
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 6) {
                Spacer()
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach([0, 1, 3, 5, 7], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(legendColor(level))
                        .frame(width: 11, height: 11)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func buildHeatmap(weeks n: Int) -> [[StatsStore.DayStat?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        guard let thisMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today),
              let startDate  = cal.date(byAdding: .weekOfYear, value: -(n - 1), to: thisMonday)
        else { return [] }

        let allDays = StatsStore.shared.history(days: n * 7 + 7)
        var lookup: [String: StatsStore.DayStat] = [:]
        for day in allDays { lookup[DateFormatter.yyyyMMdd.string(from: day.date)] = day }

        var result: [[StatsStore.DayStat?]] = []
        for w in 0..<n {
            var week: [StatsStore.DayStat?] = []
            for d in 0..<7 {
                guard let date = cal.date(byAdding: .day, value: w * 7 + d, to: startDate) else {
                    week.append(nil); continue
                }
                if date > today {
                    week.append(nil)
                } else {
                    let key = DateFormatter.yyyyMMdd.string(from: date)
                    week.append(lookup[key] ?? StatsStore.DayStat(date: date, sessions: 0, focusMinutes: 0))
                }
            }
            result.append(week)
        }
        return result
    }

    private func monthLabels(for weeks: [[StatsStore.DayStat?]]) -> [String?] {
        var labels = [String?]()
        var prevMonth = -1
        var lastLabelIdx = -4
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        for (idx, week) in weeks.enumerated() {
            if let first = week.compactMap({ $0 }).first {
                let m = cal.component(.month, from: first.date)
                if m != prevMonth {
                    prevMonth = m
                    if idx - lastLabelIdx >= 3 {
                        labels.append(fmt.string(from: first.date))
                        lastLabelIdx = idx
                    } else {
                        labels.append(nil)
                    }
                } else {
                    labels.append(nil)
                }
            } else {
                labels.append(nil)
            }
        }
        return labels
    }

    private func cellColor(for stat: StatsStore.DayStat?) -> Color {
        guard let stat = stat else { return .clear }
        switch stat.sessions {
        case 0:      return Color.secondary.opacity(0.1)
        case 1:      return Color.red.opacity(0.3)
        case 2...3:  return Color.red.opacity(0.55)
        case 4...5:  return Color.red.opacity(0.75)
        default:     return Color.red
        }
    }

    private func legendColor(_ level: Int) -> Color {
        switch level {
        case 0:  return Color.secondary.opacity(0.1)
        case 1:  return Color.red.opacity(0.3)
        case 3:  return Color.red.opacity(0.55)
        case 5:  return Color.red.opacity(0.75)
        default: return Color.red
        }
    }

    private func cellTooltip(_ stat: StatsStore.DayStat?) -> String {
        guard let stat = stat else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        let ds = fmt.string(from: stat.date)
        switch stat.sessions {
        case 0:  return "\(ds) · no sessions"
        case 1:  return "\(ds) · 1 session"
        default: return "\(ds) · \(stat.sessions) sessions"
        }
    }

    // MARK: - Metric picker

    private var metricPicker: some View {
        HStack(spacing: 2) {
            ForEach(Metric.allCases, id: \.self) { m in
                Button { metric = m } label: {
                    Text(m.localizedName)
                        .font(.subheadline.weight(metric == m ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(metric == m ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(metric == m ? Color.accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Chart

    private var barChart: some View {
        Chart(data, id: \.date) { day in
            BarMark(
                x: .value("Date", day.date, unit: .day),
                y: .value(metric.rawValue, metricValue(day))
            )
            .foregroundStyle(barColor(day))
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : range == 14 ? 2 : 7)) { val in
                if let d = val.as(Date.self) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel {
                        Text(axisLabel(d))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let v = val.as(Int.self) {
                        Text(metric == .sessions ? "\(v)" : "\(v)m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: 0...(maxValue + 1))
        .frame(height: 180)
        .animation(.easeInOut(duration: 0.3), value: metric)
        .animation(.easeInOut(duration: 0.3), value: range)
    }

    private func metricValue(_ day: StatsStore.DayStat) -> Int {
        metric == .sessions ? day.sessions : day.focusMinutes
    }

    private func barColor(_ day: StatsStore.DayStat) -> Color {
        let base: Color = metric == .sessions ? .red : .blue
        return day.isToday ? base : base.opacity(0.55)
    }

    private var maxValue: Int {
        data.map { metricValue($0) }.max() ?? 1
    }

    private func axisLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        let fmt = DateFormatter()
        fmt.dateFormat = range == 7 ? "EEE" : "MMM d"
        return fmt.string(from: date)
    }
}
