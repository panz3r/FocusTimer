import SwiftUI

/// Schedules pane: active-schedule picker, the schedule editor (name,
/// steps, long-break cadence, daily goal, repeat mode), all locked while
/// a session runs (locked decision: no mid-session schedule changes).
struct SchedulesPane: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject private var scheduleStore = ScheduleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pickerCard
            runStateCaption
            editorCard
                .disabled(engine.isRunning)
        }
    }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow("Schedule") {
                Picker("", selection: scheduleSelection) {
                    ForEach(scheduleStore.schedules) { schedule in
                        Text(schedule.name).tag(schedule.id)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .disabled(engine.isRunning)
            }
            .settingsCard()

            if engine.isRunning {
                Text("Reset the timer to edit or switch schedules.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runStateCaption: some View { EmptyView() }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                SettingsRow("Name") {
                    TextField("Schedule name", text: scheduleName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }
                Divider()

                ForEach($engine.currentSchedule.steps) { $step in
                    stepEditorRow($step)
                }
                Divider()
                SettingsRow("Add step") {
                    Button("Add…") { engine.addStepToCurrentSchedule() }
                }

                if engine.currentSchedule.hasLongBreak {
                    Divider()
                    SettingsRow("Auto long break") {
                        Toggle("", isOn: autoLongBreak).labelsHidden()
                    }
                    if autoLongBreak.wrappedValue {
                        Divider()
                        SettingsRow("Every N work steps") {
                            Stepper(value: longBreakCadence, in: 2...8) {
                                Text(verbatim: "\(longBreakCadence.wrappedValue) work steps")
                            }
                            .font(.callout)
                        }
                        Divider()
                        SettingsRow("Long break") {
                            Stepper(value: longBreakMinutes, in: 1...60) {
                                Text(verbatim: "\(longBreakMinutes.wrappedValue) min")
                            }
                            .font(.callout)
                        }
                    }
                }

                Divider()
                SettingsRow("Daily goal") {
                    Stepper("\(engine.currentSchedule.dailyGoal) sessions", value: $engine.currentSchedule.dailyGoal, in: 1...20)
                }

                Divider()
                SettingsRow("Repeats") {
                    Picker("", selection: repeatKind) {
                        Text("Always").tag(RepeatKind.infinite)
                        Text("N cycles").tag(RepeatKind.count)
                        Text("N minutes").tag(RepeatKind.total)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                if repeatKind.wrappedValue == .count {
                    Divider()
                    SettingsRow("Cycles") {
                        Stepper(value: repeatCount, in: 1...20) {
                            Text(verbatim: "\(repeatCount.wrappedValue)")
                        }
                        .font(.callout)
                    }
                }
                if repeatKind.wrappedValue == .total {
                    Divider()
                    SettingsRow("Total minutes") {
                        Stepper(value: repeatTotalMinutes, in: 5...480, step: 5) {
                            Text(verbatim: "\(repeatTotalMinutes.wrappedValue)")
                        }
                        .font(.callout)
                    }
                }
            }
            .settingsCard()
        }
    }

    // MARK: - Bindings

    private enum RepeatKind {
        case infinite, count, total
    }

    private var repeatKind: Binding<RepeatKind> {
        Binding(
            get: {
                switch engine.currentSchedule.repeatMode {
                case .infinite:               return .infinite
                case .count:                  return .count
                case .untilTotalMinutes:      return .total
                }
            },
            set: { kind in
                switch kind {
                case .infinite: engine.currentSchedule.repeatMode = .infinite
                case .count:    engine.currentSchedule.repeatMode = .count(2)
                case .total:    engine.currentSchedule.repeatMode = .untilTotalMinutes(120)
                }
            }
        )
    }

    private var repeatCount: Binding<Int> {
        Binding(
            get: {
                if case .count(let n) = engine.currentSchedule.repeatMode { return n }
                return 2
            },
            set: { engine.currentSchedule.repeatMode = .count($0) }
        )
    }

    private var repeatTotalMinutes: Binding<Int> {
        Binding(
            get: {
                if case .untilTotalMinutes(let m) = engine.currentSchedule.repeatMode { return m }
                return 120
            },
            set: { engine.currentSchedule.repeatMode = .untilTotalMinutes($0) }
        )
    }

    private var autoLongBreak: Binding<Bool> {
        Binding(
            get: { engine.currentSchedule.insertedLongBreakEvery != nil },
            set: { enabled in
                engine.currentSchedule.insertedLongBreakEvery = enabled ? 4 : nil
                if enabled, engine.currentSchedule.longBreak == nil {
                    engine.currentSchedule.longBreak = Step(
                        label: Step.Kind.longBreak.defaultLabel,
                        minutes: 15,
                        kind: .longBreak
                    )
                }
            }
        )
    }

    private var longBreakCadence: Binding<Int> {
        Binding(
            get: { engine.currentSchedule.insertedLongBreakEvery ?? 4 },
            set: { engine.currentSchedule.insertedLongBreakEvery = $0 }
        )
    }

    private var longBreakMinutes: Binding<Int> {
        Binding(
            get: { engine.currentSchedule.longBreak?.minutes ?? 15 },
            set: { engine.currentSchedule.longBreak?.minutes = $0 }
        )
    }

    private var scheduleSelection: Binding<UUID> {
        Binding(
            get: { engine.currentSchedule.id },
            set: { engine.switchSchedule(to: $0) }
        )
    }

    private var scheduleName: Binding<String> {
        Binding(
            get: { engine.currentSchedule.name },
            set: { engine.currentSchedule.name = $0.isEmpty ? "Untitled" : $0 }
        )
    }

    private func stepEditorRow(_ step: Binding<Step>) -> some View {
        HStack(spacing: 8) {
            TextField("Label", text: step.label)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
            Stepper(value: step.minutes, in: 1...240) {
                Text(verbatim: "\(step.wrappedValue.minutes) min")
            }
            .font(.callout)
            Picker("", selection: step.kind) {
                Text("Focus").tag(Step.Kind.work)
                Text("Break").tag(Step.Kind.break)
            }
            .labelsHidden()
            .frame(width: 86)
            Button("✕") { engine.removeStepFromCurrentSchedule(step.id) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove step")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
