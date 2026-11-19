import Testing
@testable import FocusTimer

/// Area 4: pure progression engine (Schedule.nextStep) — cadence upgrades,
/// budget trim, repeat-mode completion.
@Suite("Schedule Progression")
struct ScheduleProgressionTests {

    private func walk(_ schedule: Schedule, iterations: Int) -> (kinds: [Step.Kind], minutes: [Int]) {
        var step = schedule.steps[0]
        var index = 0
        var workSteps = 0
        var accumulated = 0
        var cycles = 0
        var kinds: [Step.Kind] = []
        var minutes: [Int] = [step.minutes]

        for _ in 0..<iterations {
            if step.kind == .work { workSteps += 1 }
            accumulated += step.minutes
            guard let next = Schedule.nextStep(
                schedule: schedule,
                after: step,
                currentStepIndex: index,
                completedWorkSteps: workSteps,
                accumulatedMinutes: accumulated,
                cycleCount: cycles
            ) else { break }
            step = next.step
            index = next.index
            if next.wrapped { cycles += 1 }
            kinds.append(step.kind)
            minutes.append(step.minutes)
        }
        return (kinds, minutes)
    }

    @Test func cadenceUpgradeSequence() {
        // Legacy Pomodoro with cadence 3: the long break replaces every 3rd
        // break; the next long break lands after the 6th work completion.
        let schedule = Schedule.legacyPomodoro(work: 25, shortBreak: 5, longBreakMinutes: 15, cadence: 3)
        let result = walk(schedule, iterations: 9)
        #expect(result.kinds == [
            .break, .work, .break, .work, .longBreak, .work, .break, .work, .break
        ])
    }

    @Test func zeroWorkUpgradeGuard() {
        // Before any work completes, 0 % N == 0 must NOT upgrade the break.
        let schedule = Schedule.legacyPomodoro(work: 25, shortBreak: 5, longBreakMinutes: 15, cadence: 4)
        let next = Schedule.nextStep(
            schedule: schedule,
            after: schedule.steps[0],        // work
            currentStepIndex: 0,
            completedWorkSteps: 0,
            accumulatedMinutes: 0,
            cycleCount: 0
        )
        #expect(next?.step.kind == .break)
        #expect(next?.step.minutes == 5)   // the plain short break, not the long one
    }

    @Test func budgetTrimAndFinish() {
        let schedule = Schedule(
            name: "Budget",
            steps: [
                Step(label: "Work", minutes: 25, kind: .work),
                Step(label: "Break", minutes: 10, kind: .break)
            ],
            repeatMode: .untilTotalMinutes(30)
        )
        let result = walk(schedule, iterations: 3)
        // work 25 completes; the break is trimmed to the 5 remaining minutes;
        // completing it reaches the budget -> schedule finished.
        #expect(result.kinds == [.break])
        #expect(result.minutes == [25, 5])
    }

    @Test func countFinishAfterNCycles() {
        let schedule = Schedule(
            name: "Twice",
            steps: [
                Step(label: "Work", minutes: 25, kind: .work),
                Step(label: "Break", minutes: 5, kind: .break)
            ],
            repeatMode: .count(2)
        )
        let result = walk(schedule, iterations: 6)
        // Two full cycles (w b w b) played, then the schedule finishes —
        // kinds records NEXT-step kinds, so the 4th (final) completion
        // produces none: 3 entries.
        #expect(result.kinds == [.break, .work, .break])
    }

    @Test func captions() {
        let multi = Schedule.legacyPomodoro(work: 25, shortBreak: 5, longBreakMinutes: 15, cadence: 4)
        #expect(multi.caption(cycleCount: 0) == "Pomodoro · Cycle 1")
        #expect(multi.caption(cycleCount: 3) == "Pomodoro · Cycle 4")

        let single = Schedule(name: "Deep Work", steps: [Step(label: "Deep Work", minutes: 90, kind: .work)])
        #expect(single.caption(cycleCount: 2) == "Deep Work · Step 3")
    }
}
