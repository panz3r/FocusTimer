import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var engine: SessionEngine
    @ObservedObject private var statsStore = StatsStore.shared
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    @ObservedObject private var updater  = UpdateChecker.shared
    @ObservedObject private var updaterW = AutoUpdater.shared
    @State private var breakPrompt: String = ""
    @FocusState private var isTaskFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            TimerHeaderBar(engine: engine, labelFont: .title3.weight(.semibold), spacing: 8)

            RemoteSessionCaptionView(coordinator: syncCoordinator, engine: engine)

            TaskLabelField(engine: engine, font: .callout, focus: $isTaskFieldFocused)

            TimerRingView(
                engine: engine,
                size: 240,
                trackWidth: 12,
                glowWidth: 24,
                blurRadius: 8,
                timeFontSize: 56,
                statusFont: .caption
            )

            ScheduleCaptionView(schedule: engine.currentSchedule, cycleCount: engine.cycleCount)

            StepDotsRow(
                schedule: engine.currentSchedule,
                completedWorkSteps: engine.completedWorkSteps,
                dotSize: 10,
                spacing: 12
            )

            if engine.currentStep.kind != .work, !breakPrompt.isEmpty {
                Text(breakPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TimerControlsRow(engine: engine, spacing: 16, controlSize: .large, minWidth: 80)

            Divider()

            statsRow
            GoalFooterView(engine: engine)
        }
        .padding(32)
        .frame(width: 360)
        .overlay(alignment: .top) {
            UpdateBannersView(updater: updater, autoUpdater: updaterW)
        }
        .animation(.easeInOut(duration: 0.35), value: engine.currentStep)
        .onAppear {
            if engine.currentStep.kind != .work {
                breakPrompt = BreakPrompts.roll()
            }
        }
        .onChange(of: engine.currentStep) { _, step in
            if step.kind != .work {
                breakPrompt = BreakPrompts.roll()
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack {
            statItem("\(engine.completedPomodoros)", "sessions")
            Divider().frame(height: 32)
            statItem("\(StatsStore.shared.todayFocusMinutes)", "min focus")
            Divider().frame(height: 32)
            statItem("\(StatsStore.shared.currentStreak)", "day streak")
        }
        .frame(maxWidth: .infinity)
    }

    private func statItem(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: value)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
