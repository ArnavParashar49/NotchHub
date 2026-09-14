import Foundation

/// A native timer service the app can drive (the island's own stopwatch/timer).
///
/// Kept in the system layer because it is a source of events, not UI state: it
/// ticks and emits, and the presentation layer decides what that looks like.
public final class TimerService: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var timer: Timer?
    private var startedAt: Date?

    /// Tick interval. Fine enough for a seconds display, cheap enough to ignore.
    private let interval: TimeInterval = 0.25

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    /// When the focus countdown ends, while one runs.
    public private(set) var countdownEndsAt: Date?
    private var countdownDuration: TimeInterval = 0

    public var isRunning: Bool { timer != nil }

    /// Whether the timer is counting a focus session down.
    public var isCountingDown: Bool { countdownEndsAt != nil }

    /// Whether the stopwatch (not a focus session) is running.
    public var isStopwatchRunning: Bool { startedAt != nil }

    /// Starts a focus countdown of `duration`, replacing whatever the timer was
    /// doing. Ticks report the time left; running out reports it completed.
    public func startCountdown(_ duration: TimeInterval) {
        timer?.invalidate()
        timer = nil
        // The countdown exists before anything is reported, so observers of the
        // stopwatch giving way already see a focus session.
        countdownDuration = duration
        let end = Date().addingTimeInterval(duration)
        countdownEndsAt = end
        if startedAt != nil {
            // The stopwatch gives way; its readout makes room for the countdown.
            startedAt = nil
            emit(SystemEvent(source: .timer, payload: .timerFinished))
        }
        emit(SystemEvent(source: .timer, payload: .focusTick(remaining: duration)))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let end = self.countdownEndsAt else { return }
            let remaining = end.timeIntervalSinceNow
            if remaining <= 0 {
                self.finishCountdown(completed: true)
            } else {
                self.emit(SystemEvent(source: .timer, payload: .focusTick(remaining: remaining)))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ends a focus countdown early.
    public func stopCountdown() {
        finishCountdown(completed: false)
    }

    private func finishCountdown(completed: Bool) {
        guard countdownEndsAt != nil else { return }
        timer?.invalidate()
        timer = nil
        countdownEndsAt = nil
        emit(SystemEvent(source: .timer, payload: .focusFinished(completed: completed)))
    }

    /// Starts (or restarts) the timer.
    public func startTimer() {
        finishCountdown(completed: false)
        stopTimer()
        startedAt = Date()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            self.emit(SystemEvent(source: .timer, payload: .timerTick(elapsed: elapsed)))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Report at once, so a readout that replaces a focus session takes over
        // in the same pass instead of the island blinking empty for a tick.
        emit(SystemEvent(source: .timer, payload: .timerTick(elapsed: 0)))
    }

    /// Stops the timer and reports completion (or ends a focus countdown early).
    public func stopTimer() {
        if isCountingDown {
            finishCountdown(completed: false)
            return
        }
        timer?.invalidate()
        timer = nil
        if startedAt != nil {
            startedAt = nil
            emit(SystemEvent(source: .timer, payload: .timerFinished))
        }
    }

    /// Resets the stopwatch to zero and restarts it, without emitting a
    /// `timerFinished` completion event (used by the island's Reset action).
    public func resetTimer() {
        if isCountingDown {
            // A focus session starts over.
            startCountdown(countdownDuration)
            return
        }
        timer?.invalidate()
        timer = nil
        startedAt = Date()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            self.emit(SystemEvent(source: .timer, payload: .timerTick(elapsed: elapsed)))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - SystemListener

    public func start() { /* Started on demand via startTimer(). */ }

    public func stop() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        countdownEndsAt = nil
    }
}
