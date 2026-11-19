import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: TimerViewModel
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    @ObservedObject private var updater  = UpdateChecker.shared
    @ObservedObject private var updaterW = AutoUpdater.shared
    @State private var breakPrompt: String = ""
    @FocusState private var isTaskFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            TimerHeaderBar(vm: vm, labelFont: .headline, spacing: 7)

            TaskLabelField(vm: vm, font: .caption, focus: $isTaskFieldFocused)

            RemoteSessionCaptionView(coordinator: syncCoordinator, vm: vm)

            TimerRingView(
                vm: vm,
                size: 180,
                trackWidth: 10,
                glowWidth: 20,
                blurRadius: 6,
                timeFontSize: 40,
                statusFont: .caption2
            )

            StepDotsRow(
                schedule: vm.currentSchedule,
                completedWorkSteps: vm.completedWorkSteps,
                dotSize: 8,
                spacing: 10
            )

            ScheduleCaptionView(schedule: vm.currentSchedule, cycleCount: vm.cycleCount)

            // Break prompt
            if vm.currentStep.kind != .work, !breakPrompt.isEmpty {
                Text(breakPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TimerControlsRow(vm: vm, spacing: 14, minWidth: 56)

            UpdateBannersView(updater: updater, autoUpdater: updaterW)

            Divider()

            GoalFooterView(vm: vm, showsQuitButton: true)
        }
        .padding(24)
        .frame(width: 300)
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
}
