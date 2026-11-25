import SwiftUI

/// Area 4: a data-driven timer schedule replacing the hard-coded Pomodoro
/// cycle. `steps` rotate in order; `longBreak` (when present) replaces the
/// next break after every `insertedLongBreakEvery` completed work steps.
struct Schedule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var steps: [Step]
    var longBreak: Step? = nil
    var insertedLongBreakEvery: Int? = nil
    var repeatMode: RepeatMode = .infinite
    /// Task label remembered when a non-work step clears it (item I).
    var lastUsedLabel: String? = nil
    /// Daily goal target for this schedule (work steps only, decision D).
    var dailyGoal: Int = 8

    var hasLongBreak: Bool { longBreak != nil }

    /// Popover/main-window caption ("Pomodoro · Cycle 2" for multi-step
    /// schedules; "Deep Work · Step 3" for single-step ones).
    func caption(cycleCount: Int) -> String {
        if steps.count > 1 {
            return "\(name) · Cycle \(cycleCount + 1)"
        }
        return "\(name) · Step \(cycleCount + 1)"
    }

    /// Pure progression engine (Area 4): given the just-completed step and
    /// the running totals, returns the next step — or nil when the schedule
    /// has finished (`.count` cycles played, or `.untilTotalMinutes` budget
    /// reached). Pure so it can be verified headlessly.
    static func nextStep(
        schedule: Schedule,
        after finishedStep: Step,
        currentStepIndex: Int,
        completedWorkSteps: Int,
        accumulatedMinutes: Int,
        cycleCount: Int
    ) -> (step: Step, index: Int, wrapped: Bool, finished: Bool)? {
        guard !schedule.steps.isEmpty else { return nil }

        let nextIndex = (currentStepIndex + 1) % schedule.steps.count
        let wrapped = nextIndex == 0
        let nextCycleCount = cycleCount + (wrapped ? 1 : 0)

        switch schedule.repeatMode {
        case .count(let n):
            if wrapped, nextCycleCount >= n { return nil }
        case .untilTotalMinutes(let budget):
            if accumulatedMinutes >= budget { return nil }
        case .infinite:
            break
        }

        var nextStep = schedule.steps[nextIndex]

        // Long-break upgrade: after every Nth completed work step, the next
        // break is served as the schedule's long break (legacy parity: the
        // Nth work session is followed by the long break instead of a short
        // one). Requires at least one completed work step — 0 % N == 0 must
        // not upgrade before any work has happened.
        if finishedStep.kind == .work,
           nextStep.kind == .break,
           let cadence = schedule.insertedLongBreakEvery, cadence > 0,
           completedWorkSteps > 0,
           completedWorkSteps % cadence == 0,
           let longBreak = schedule.longBreak {
            nextStep = longBreak
        }

        // Budget trim: the final step plays only the minutes that remain.
        if case .untilTotalMinutes(let budget) = schedule.repeatMode {
            let left = budget - accumulatedMinutes
            if left < nextStep.minutes {
                nextStep.minutes = max(1, left)
            }
        }

        return (nextStep, nextIndex, wrapped, false)
    }

    /// The default (pre-schedules) strategy's name — also the fallback
    /// schedule name for session-log entries recorded before schedules
    /// existed.
    static let legacyName = "Pomodoro"

    /// Compact description for pickers ("25/5 × 4 → 15 long break").
    var summary: String {
        var text = steps.map { "\($0.minutes)" }.joined(separator: "/")
        if let cadence = insertedLongBreakEvery, let longBreak {
            text += " × \(cadence) → \(longBreak.minutes) long break"
        }
        return text
    }

    // MARK: - Built-in presets (seeded once; editable afterwards)

    static func legacyPomodoro(work: Int, shortBreak: Int,
                               longBreakMinutes: Int, cadence: Int) -> Schedule {
        Schedule(
            name: "Pomodoro",
            steps: [
                // "Work" is the traditional Pomodoro term — the schedule
                // keeps it even though the generic type is named "Focus".
                Step(label: "Work", minutes: work, kind: .work),
                Step(label: Step.Kind.break.defaultLabel, minutes: shortBreak, kind: .break)
            ],
            longBreak: Step(label: Step.Kind.longBreak.defaultLabel, minutes: longBreakMinutes, kind: .longBreak),
            insertedLongBreakEvery: cadence
        )
    }

    static var seedPresets: [Schedule] {
        [
            legacyPomodoro(work: 25, shortBreak: 5, longBreakMinutes: 15, cadence: 4),
            Schedule(
                name: "Deep Work",
                steps: [Step(label: "Deep Work", minutes: 90, kind: .work)],
                repeatMode: .infinite
            ),
            Schedule(
                name: "52/17 Flowtime",
                steps: [
                    Step(label: Step.Kind.work.defaultLabel, minutes: 52, kind: .work),
                    Step(label: "Break", minutes: 17, kind: .break)
                ]
            ),
            Schedule(
                name: "Sprint Focus",
                steps: [
                    Step(label: Step.Kind.work.defaultLabel, minutes: 60, kind: .work),
                    Step(label: "Break", minutes: 10, kind: .break)
                ]
            )
        ]
    }
}

enum RepeatMode: Codable, Equatable {
    case infinite
    case count(Int)                 // run the schedule N full cycles
    case untilTotalMinutes(Int)     // stop after N minutes of completed steps
}

// Tolerant decoding: fields added after v1 (like dailyGoal) default
// gracefully when missing from older stores/backups, instead of failing
// the whole decode. Lives in an extension so the memberwise init survives.
extension Schedule {
    enum CodingKeys: String, CodingKey {
        case id, name, steps, longBreak, insertedLongBreakEvery, repeatMode, lastUsedLabel, dailyGoal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id   = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        steps = try container.decodeIfPresent([Step].self, forKey: .steps) ?? []
        longBreak = try container.decodeIfPresent(Step.self, forKey: .longBreak)
        insertedLongBreakEvery = try container.decodeIfPresent(Int.self, forKey: .insertedLongBreakEvery)
        repeatMode = try container.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .infinite
        lastUsedLabel = try container.decodeIfPresent(String.self, forKey: .lastUsedLabel)
        dailyGoal = try container.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 8
    }
}

struct Step: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String
    var minutes: Int
    var kind: Kind

    enum Kind: String, Codable, CaseIterable {
        case work, `break`, longBreak
    }
}

extension Step.Kind {
    /// Localized display name — used for cross-Mac captions and
    /// notification titles. (defaultLabel stays English: it seeds
    /// stored step data, per the localization decisions.)
    var localizedName: String {
        switch self {
        case .work:      return String(localized: "Focus")
        case .break:     return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long break")
        }
    }

    var defaultLabel: String {
        switch self {
        case .work:      return "Focus"
        case .break:     return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var defaultColor: Color {
        switch self {
        case .work:      return .red
        case .break:     return .green
        case .longBreak: return .teal
        }
    }

    var sfSymbol: String {
        switch self {
        case .work:      return "timer"
        case .break:     return "cup.and.saucer"
        case .longBreak: return "leaf"
        }
    }
}
