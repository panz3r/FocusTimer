import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: SessionEngine
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    @ObservedObject private var updater  = UpdateChecker.shared
    @ObservedObject private var updaterW = AutoUpdater.shared
    @State private var breakPrompt: String = ""
    @FocusState private var isTaskFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            TimerHeaderBar(engine: engine, labelFont: .headline, spacing: 7)

            TaskLabelField(engine: engine, font: .caption, focus: $isTaskFieldFocused)

            RemoteSessionCaptionView(coordinator: syncCoordinator, engine: engine)

            TimerRingView(
                engine: engine,
                size: 180,
                trackWidth: 10,
                glowWidth: 20,
                blurRadius: 6,
                timeFontSize: 40,
                statusFont: .caption2
            )

            StepDotsRow(
                schedule: engine.currentSchedule,
                completedWorkSteps: engine.completedWorkSteps,
                dotSize: 8,
                spacing: 10
            )

            ScheduleCaptionView(schedule: engine.currentSchedule, cycleCount: engine.cycleCount)

            // Break prompt
            if engine.currentStep.kind != .work, !breakPrompt.isEmpty {
                Text(breakPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TimerControlsRow(engine: engine, spacing: 14, minWidth: 56)

            UpdateBannersView(updater: updater, autoUpdater: updaterW)

            Divider()

            GoalFooterView(engine: engine, showsQuitButton: true)
        }
        .padding(24)
        .frame(width: 300)
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
}
