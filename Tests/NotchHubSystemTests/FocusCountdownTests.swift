import Foundation
import Testing
@testable import NotchHubCore
@testable import NotchHubSystem

@Suite("Focus countdown")
@MainActor
struct FocusCountdownTests {

    final class Log {
        var payloads: [SystemEvent.Payload] = []
    }

    @Test("a focus session counts down, can be stopped, and gives way to the stopwatch")
    func countdown() {
        let log = Log()
        let service = TimerService { log.payloads.append($0.payload) }
        service.startCountdown(1500)
        #expect(service.isCountingDown)
        #expect(service.isRunning)
        guard case let .focusTick(remaining)? = log.payloads.last else {
            Issue.record("no tick when the countdown starts")
            return
        }
        #expect(remaining == 1500)

        service.stopCountdown()
        #expect(!service.isCountingDown)
        #expect(!service.isRunning)
        guard case let .focusFinished(completed)? = log.payloads.last else {
            Issue.record("no finish when the countdown stops")
            return
        }
        #expect(!completed)

        log.payloads.removeAll()
        service.startCountdown(60)
        service.startTimer()
        #expect(!service.isCountingDown)
        #expect(log.payloads.contains { if case .focusFinished(completed: false) = $0 { return true } else { return false } })
        service.stop()
    }

    final class Watch {
        weak var service: TimerService?
        var countingDownAtStopwatchFinish: Bool?
    }

    @Test("a focus session replacing the stopwatch is already counting down when the stopwatch reports it gave way")
    func handOff() {
        let watch = Watch()
        let service = TimerService { event in
            if case .timerFinished = event.payload {
                watch.countingDownAtStopwatchFinish = watch.service?.isCountingDown
            }
        }
        watch.service = service
        service.startTimer()
        #expect(service.isStopwatchRunning)
        service.startCountdown(60)
        #expect(watch.countingDownAtStopwatchFinish == true)
        #expect(!service.isStopwatchRunning)
        #expect(service.isCountingDown)
        service.startTimer()
        #expect(service.isStopwatchRunning)
        #expect(!service.isCountingDown)
        service.stop()
    }

    @Test("the stopwatch reports as it starts, so it takes over a focus readout without a gap")
    func stopwatchReportsAtOnce() {
        let log = Log()
        let service = TimerService { log.payloads.append($0.payload) }
        service.startCountdown(60)
        service.startTimer()
        guard case let .timerTick(elapsed)? = log.payloads.last else {
            Issue.record("the stopwatch did not report as it started")
            return
        }
        #expect(elapsed == 0)
        service.stop()
    }

    @Test("the island shows a focus countdown as a Focus timer counting whole seconds down")
    func bridge() {
        let tick = ActivityBridge.instructions(for: SystemEvent(source: .timer, payload: .focusTick(remaining: 1499.2)))
        guard case let .upsert(activity)? = tick.first else {
            Issue.record("expected an upsert")
            return
        }
        #expect(activity.title == "Focus")
        #expect(activity.elapsed == 1500)
        let done = ActivityBridge.instructions(for: SystemEvent(source: .timer, payload: .focusFinished(completed: true)))
        guard case .remove(.timer)? = done.first else {
            Issue.record("expected the timer to go")
            return
        }
    }
}
