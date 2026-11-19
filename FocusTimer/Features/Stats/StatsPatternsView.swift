import SwiftUI
import Charts

/// Patterns tab: the time-of-day distribution of completed sessions, with
/// the peak hour highlighted.
struct StatsPatternsView: View {
    let range: Int
    @ObservedObject private var statsStore = StatsStore.shared

    private struct HourBucket: Identifiable {
        let hour: Int
        let count: Int
        var id: Int { hour }
    }

    private var hourData: [HourBucket] {
        let entries = StatsStore.shared.recentEntries(days: range)
        var counts = Array(repeating: 0, count: 24)
        let cal = Calendar.current
        for entry in entries { counts[cal.component(.hour, from: entry.timestamp)] += 1 }
        return counts.enumerated().map { HourBucket(hour: $0.offset, count: $0.element) }
    }

    private var peakHour: HourBucket? {
        hourData.filter { $0.count > 0 }.max(by: { $0.count < $1.count })
    }

    var body: some View {
        VStack(spacing: 0) {
            let entries = StatsStore.shared.recentEntries(days: range)
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No sessions in this range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Complete work sessions to see your peak hours.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 20) {
                    if let peak = peakHour {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Peak focus hour")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(hourLabel(peak.hour, style: .full))
                                    .font(.title3.weight(.semibold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Sessions at peak")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text("\(peak.count)")
                                    .font(.title3.weight(.semibold))
                            }
                        }
                    }

                    Chart(hourData) { bucket in
                        BarMark(
                            x: .value("Hour", bucket.hour),
                            y: .value("Sessions", bucket.count)
                        )
                        .foregroundStyle(
                            bucket.hour == peakHour?.hour
                                ? Color.red
                                : Color.red.opacity(0.4)
                        )
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { val in
                            if let h = val.as(Int.self) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.secondary.opacity(0.2))
                                AxisValueLabel {
                                    Text(hourLabel(h, style: .short))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { val in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.secondary.opacity(0.2))
                            AxisValueLabel {
                                if let v = val.as(Int.self) {
                                    Text("\(v)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartYScale(domain: 0...(max(hourData.map(\.count).max() ?? 0, 1) + 1))
                    .frame(height: 180)
                    .animation(.easeInOut(duration: 0.3), value: range)
                }
                .padding(24)
                Divider()
                StatsFooterView(
                    data: StatsStore.shared.history(days: range),
                    range: range
                )
            }
        }
    }

    private enum HourLabelStyle { case short, full }
    private func hourLabel(_ hour: Int, style: HourLabelStyle) -> String {
        switch style {
        case .short:
            switch hour {
            case 0:  return "12a"
            case 12: return "12p"
            default: return hour < 12 ? "\(hour)a" : "\(hour - 12)p"
            }
        case .full:
            switch hour {
            case 0:  return "12:00 AM"
            case 12: return "12:00 PM"
            default: return hour < 12 ? "\(hour):00 AM" : "\(hour - 12):00 PM"
            }
        }
    }
}
