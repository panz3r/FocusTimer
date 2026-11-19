import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var vm: TimerViewModel
    @ObservedObject private var statsStore = StatsStore.shared
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    @ObservedObject private var updater  = UpdateChecker.shared
    @ObservedObject private var updaterW = AutoUpdater.shared
    @State private var breakPrompt: String = ""
    @FocusState private var isTaskFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            TimerHeaderBar(vm: vm, labelFont: .title3.weight(.semibold), spacing: 8)

            RemoteSessionCaptionView(coordinator: syncCoordinator, vm: vm)

            TaskLabelField(vm: vm, font: .callout, focus: $isTaskFieldFocused)

            TimerRingView(
                vm: vm,
                size: 240,
                trackWidth: 12,
                glowWidth: 24,
                blurRadius: 8,
                timeFontSize: 56,
                statusFont: .caption
            )

            ScheduleCaptionView(schedule: vm.currentSchedule, cycleCount: vm.cycleCount)

            StepDotsRow(
                schedule: vm.currentSchedule,
                completedWorkSteps: vm.completedWorkSteps,
                dotSize: 10,
                spacing: 12
            )

            if vm.currentStep.kind != .work, !breakPrompt.isEmpty {
                Text(breakPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TimerControlsRow(vm: vm, spacing: 16, controlSize: .large, minWidth: 80)

            Divider()

            statsRow
            GoalFooterView(vm: vm)
        }
        .padding(32)
        .frame(width: 360)
        .overlay(alignment: .top) {
            UpdateBannersView(updater: updater, autoUpdater: updaterW)
        }
        .animation(.easeInOut(duration: 0.35), value: vm.currentStep)
        .onAppear {
            if vm.currentStep.kind != .work {
                breakPrompt = BreakPrompts.roll()
            }
        }
        .onChange(of: vm.currentStep) { _, step in
            if step.kind != .work {
                breakPrompt = BreakPrompts.roll()
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack {
            statItem("\(vm.completedPomodoros)", "sessions")
            Divider().frame(height: 32)
            statItem("\(StatsStore.shared.todayFocusMinutes)", "min focus")
            Divider().frame(height: 32)
            statItem("\(StatsStore.shared.currentStreak)", "day streak")
        }
        .frame(maxWidth: .infinity)
    }

    private func statItem(_ value: String, _ label: String) -> some View {
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
