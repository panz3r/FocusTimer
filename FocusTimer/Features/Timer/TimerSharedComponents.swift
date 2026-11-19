import SwiftUI

/// Phase 2: components shared by the popover (ContentView) and the main
/// window (MainWindowView). Both compose these; the two bodies only differ
/// in sizing/layout, not in the pieces.
///
/// Easter-egg state (ring taps, secret status) is ring-local and lives
/// inside TimerRingView.

// MARK: - Break prompts

enum BreakPrompts {
    static let all = [
        "Stand up and stretch for a minute.",
        "Get some water.",
        "Look out a window — give your eyes a rest.",
        "Take 5 slow, deep breaths.",
        "Roll your shoulders back and relax your jaw.",
        "Walk to another room and back.",
        "Close your eyes and rest for 30 seconds.",
        "Do a quick neck stretch — left, right, forward.",
        "Step outside if you can — even for 60 seconds.",
        "Refill your coffee or tea.",
    ]

    static func roll() -> String { all.randomElement() ?? "" }
}

// MARK: - Header bar

/// Icon + step label on the left; Social (gated), Stats and Settings
/// buttons on the right.
struct TimerHeaderBar: View {
    @ObservedObject var engine: SessionEngine
    var labelFont: Font = .headline
    var spacing: CGFloat = 7

    private var socialAvailable: Bool {
        SocialConfig.load().isExplicitlyEnabled
    }

    var body: some View {
        HStack {
            HStack(spacing: spacing) {
                Image(systemName: engine.currentStep.kind.sfSymbol)
                    .foregroundStyle(engine.currentStep.kind.defaultColor)
                    .id("icon-\(engine.currentStep.id)")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))

                Text(engine.currentStep.label)
                    .font(labelFont)
                    .id("label-\(engine.currentStep.id)")
                    .transition(.opacity)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: engine.currentStep)

            Spacer()

            HStack(spacing: 12) {
                if socialAvailable {
                    Button { SocialWindowController.shared.open() } label: {
                        Image(systemName: "person.2").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button { StatsWindowController.shared.open() } label: {
                    Image(systemName: "chart.bar").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    // The header bar only carries the engine; fetch the
                    // settings singleton for the settings window.
                    SettingsWindowController.shared.open(
                        engine: SessionEngine.shared,
                        settings: AppSettings.shared
                    )
                } label: {
                    Image(systemName: "gearshape").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Task label (+ autocomplete)

struct TaskLabelField: View {
    @ObservedObject var engine: SessionEngine
    var font: Font = .caption
    var focus: FocusState<Bool>.Binding

    private var filteredSuggestions: [String] {
        let all = StatsStore.shared.recentLabels(limit: 8)
        let query = engine.taskLabel.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) && $0.lowercased() != query.lowercased() }
    }

    var body: some View {
        VStack(spacing: 4) {
            TextField("What are you working on?", text: $engine.taskLabel)
                .font(font)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .truncationMode(.tail)
                .focused(focus)

            if focus.wrappedValue && !filteredSuggestions.isEmpty {
                suggestionsView
            }
        }
    }

    private var suggestionsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredSuggestions.prefix(5).enumerated()), id: \.element) { _, label in
                if label != filteredSuggestions.first { Divider() }
                Button {
                    engine.taskLabel = label
                    focus.wrappedValue = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}

// MARK: - Progress ring (includes the glow pulse + ring-tap easter egg)

struct TimerRingView: View {
    @ObservedObject var engine: SessionEngine
    var size: CGFloat
    var trackWidth: CGFloat
    var glowWidth: CGFloat
    var blurRadius: CGFloat
    var timeFontSize: CGFloat
    var statusFont: Font
    var initialGlowOpacity: Double = 0.2

    @State private var glowOpacity: Double
    @State private var ringTapCount = 0
    @State private var secretActive = false

    init(engine: SessionEngine, size: CGFloat, trackWidth: CGFloat, glowWidth: CGFloat,
         blurRadius: CGFloat, timeFontSize: CGFloat, statusFont: Font,
         initialGlowOpacity: Double = 0.2) {
        self.engine = engine
        self.size = size
        self.trackWidth = trackWidth
        self.glowWidth = glowWidth
        self.blurRadius = blurRadius
        self.timeFontSize = timeFontSize
        self.statusFont = statusFont
        self.initialGlowOpacity = initialGlowOpacity
        _glowOpacity = State(initialValue: initialGlowOpacity)
    }

    private var color: Color { engine.currentStep.kind.defaultColor }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: trackWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(color.opacity(glowOpacity),
                        style: StrokeStyle(lineWidth: glowWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .blur(radius: blurRadius)
                .animation(.linear(duration: 0.9), value: engine.progress)

            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(color, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: engine.progress)

            VStack(spacing: 6) {
                Text(engine.formattedTime)
                    .font(.system(size: timeFontSize, weight: .thin, design: .monospaced))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: engine.formattedTime)

                Text(statusLabel)
                    .font(statusFont)
                    .foregroundStyle(.secondary)
                    .id("status-\(statusLabel)")
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: statusLabel)
            }
        }
        // Pulse the glow while running
        .onChange(of: engine.isRunning) { _, running in
            if running {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.45
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { glowOpacity = 0.0 }
            }
        }
        // Five ring taps reveal the easter egg
        .onTapGesture {
            ringTapCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { ringTapCount = 0 }
            if ringTapCount >= 5 {
                ringTapCount = 0
                secretActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { secretActive = false }
            }
        }
    }

    private var statusLabel: String {
        if secretActive { return "🎉 you found it!" }
        if engine.isRunning {
            switch engine.taskLabel.trimmingCharacters(in: .whitespaces).lowercased() {
            case "🍅":                  return "🍅 in progress"
            case "coffee", "☕":        return "☕ brewing"
            case "42":                  return "the answer 🌌"
            case "debug", "debugging":  return "🐛 squashing bugs"
            default:                    return "in progress"
            }
        }
        if engine.progress > 0 { return "paused" }
        return "ready"
    }
}

// MARK: - Step dots (completed work steps toward the long break)

struct StepDotsRow: View {
    let schedule: Schedule
    let completedWorkSteps: Int
    var dotSize: CGFloat = 8
    var spacing: CGFloat = 10

    private var color: Color { schedule.steps.first?.kind.defaultColor ?? .red }

    var body: some View {
        Group {
            if let cadence = schedule.insertedLongBreakEvery, schedule.hasLongBreak {
                HStack(spacing: spacing) {
                    ForEach(0..<cadence, id: \.self) { i in
                        let filled = i < (completedWorkSteps % cadence)
                        Circle()
                            .fill(filled ? color : Color.secondary.opacity(0.25))
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(filled ? 1.25 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: filled)
                    }
                }
            }
        }
    }
}

// MARK: - Captions

struct ScheduleCaptionView: View {
    let schedule: Schedule
    let cycleCount: Int

    var body: some View {
        Text(schedule.caption(cycleCount: cycleCount))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// Area 3: a session running on another Mac (shown while this one is idle).
struct RemoteSessionCaptionView: View {
    @ObservedObject var coordinator: SyncCoordinator
    @ObservedObject var engine: SessionEngine

    var body: some View {
        Group {
            if let remote = coordinator.remoteActiveSession, !engine.isRunning {
                Text("\(remote.type) on \(remote.host) · \(remote.remainingSeconds / 60)m left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Controls row

struct TimerControlsRow: View {
    @ObservedObject var engine: SessionEngine
    var spacing: CGFloat = 14
    var controlSize: ControlSize = .regular
    var minWidth: CGFloat = 56

    private var color: Color { engine.currentStep.kind.defaultColor }

    var body: some View {
        HStack(spacing: spacing) {
            Button("Reset") { engine.reset() }
                .buttonStyle(.bordered)
                .controlSize(controlSize)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { engine.toggleTimer() }
            } label: {
                Text(engine.isRunning ? "Pause" : "Start")
                    .frame(minWidth: minWidth)
                    .contentTransition(.interpolate)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            .controlSize(controlSize)
            .animation(.easeInOut(duration: 0.2), value: color)

            Button("Skip") { engine.skip() }
                .buttonStyle(.bordered)
                .controlSize(controlSize)
        }
    }
}

// MARK: - Goal footer

struct GoalFooterView: View {
    @ObservedObject var engine: SessionEngine
    var showsQuitButton = false

    private var color: Color { engine.currentStep.kind.defaultColor }

    var body: some View {
        let done    = engine.completedPomodoros
        let goal    = engine.dailyGoal
        let reached = done >= goal

        return VStack(spacing: 6) {
            HStack {
                Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reached ? .green : color)
                    .font(.caption)

                Text(reached ? "Goal reached · \(done) sessions" : "\(done) of \(goal) sessions today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: done)

                Spacer()

                if showsQuitButton {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 3)
                    Capsule()
                        .fill(reached ? Color.green : color)
                        .frame(
                            width: min(geo.size.width * CGFloat(done) / CGFloat(max(goal, 1)), geo.size.width),
                            height: 3
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: done)
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Update / error banners

struct UpdateBannersView: View {
    @ObservedObject var updater: UpdateChecker
    @ObservedObject var autoUpdater: AutoUpdater

    var body: some View {
        VStack(spacing: 6) {
            if let ver = updater.availableVersion { updateBanner(ver) }
            if case .failed(let msg) = autoUpdater.phase { errorBanner(msg) }
        }
    }

    private func updateBanner(_ ver: String) -> some View {
        Group {
            switch autoUpdater.phase {
            case .idle:
                Button {
                    if let url = updater.downloadURL {
                        AutoUpdater.shared.startUpdate(from: url)
                    } else {
                        NSWorkspace.shared.open(URL(string: "https://github.com/lumenworksco/FocusTimer/releases/latest")!)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle")
                        Text("v\(ver) available — Update Now")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)

            case .downloading(let p):
                VStack(spacing: 3) {
                    Text("Downloading… \(Int(p * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                    GeometryReader { geo in
                        Capsule().fill(Color.white.opacity(0.35)).frame(height: 3)
                        Capsule().fill(Color.white).frame(width: geo.size.width * p, height: 3)
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            case .installing:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).colorScheme(.dark)
                    Text("Installing…")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            case .failed:
                EmptyView()
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
            Text(msg)
            Spacer()
            Button("✕") { AutoUpdater.shared.phase = .idle }.font(.caption2.weight(.bold))
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.red.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
