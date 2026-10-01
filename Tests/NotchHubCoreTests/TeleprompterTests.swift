import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Teleprompter")
struct TeleprompterTests {

    private let frame = CGRect(x: 100, y: 700, width: 560, height: 196)
    private let notchInset: CGFloat = 32

    private func loaded(_ text: String = "line one\nline two\nline three", distance: Double = 600) -> TeleprompterState {
        var state = TeleprompterState()
        state.load(text)
        state.scrollDistance = distance
        return state
    }

    // MARK: - Scrolling

    @Test("the offset comes from the clock, so the scroll is exactly constant")
    func constantScroll() {
        var state = loaded()
        let start = Date()
        state.play(now: start)

        // Sampled at wildly uneven intervals — a dropped frame, a long stall —
        // the position is still exactly rate × elapsed. This is the property
        // that makes the scroll stutter-proof: nothing accumulates per frame.
        for seconds in [0.0, 0.016, 0.5, 0.517, 3.0, 9.25] {
            let expected = state.pointsPerSecond * seconds
            #expect(abs(state.offset(at: start.addingTimeInterval(seconds)) - expected) < 0.0001,
                    "drifted at \(seconds)s")
        }
    }

    @Test("pausing keeps the exact position, and resuming carries on from it")
    func pauseKeepsPosition() {
        var state = loaded()
        let start = Date()
        state.play(now: start)

        let pausedAt = start.addingTimeInterval(4)
        let position = state.offset(at: pausedAt)
        state.pause(now: pausedAt)
        #expect(!state.isRunning)
        #expect(state.offset(at: pausedAt) == position)
        // Time passing while paused moves nothing.
        #expect(state.offset(at: pausedAt.addingTimeInterval(60)) == position)

        let resumedAt = pausedAt.addingTimeInterval(60)
        state.play(now: resumedAt)
        #expect(state.offset(at: resumedAt) == position, "resuming jumped")
        #expect(abs(state.offset(at: resumedAt.addingTimeInterval(1)) - (position + state.pointsPerSecond)) < 0.0001)
    }

    @Test("changing speed does not move the text, only how fast it goes from here")
    func speedChangeDoesNotJump() {
        var state = loaded()
        let start = Date()
        state.play(now: start)
        let changeAt = start.addingTimeInterval(5)
        let position = state.offset(at: changeAt)
        let before = state.pointsPerSecond

        state.faster(now: changeAt)
        // The very same instant still reads the same position…
        #expect(abs(state.offset(at: changeAt) - position) < 0.0001, "the script jumped when the speed changed")
        // …and it is genuinely faster from here on.
        #expect(state.pointsPerSecond > before)
        let after = state.offset(at: changeAt.addingTimeInterval(1))
        #expect(abs(after - (position + state.pointsPerSecond)) < 0.0001)
    }

    @Test("speed steps stop at both ends and always read with a multiplication sign")
    func speedRange() {
        var state = loaded()
        #expect(state.speedMultiplier == 1)
        #expect(state.speedLabel == "1×")

        for _ in 0..<20 { state.faster() }
        #expect(state.speedMultiplier == TeleprompterState.speeds.last)
        #expect(!state.canGoFaster)
        for _ in 0..<20 { state.slower() }
        #expect(state.speedMultiplier == TeleprompterState.speeds.first)
        #expect(!state.canGoSlower)

        state.setSpeedIndex(3)
        #expect(state.speedLabel == "1.25×")
    }

    @Test("it parks at the end of the script instead of scrolling past it")
    func parksAtTheEnd() {
        var state = loaded(distance: 100)
        let start = Date()
        state.play(now: start)
        let wayPast = start.addingTimeInterval(10_000)
        #expect(state.offset(at: wayPast) == 100)
        #expect(state.isFinished(at: wayPast))
        #expect(state.progress(at: wayPast) == 1)

        // Playing a finished script starts it over — what you want from a
        // second take.
        state.play(now: wayPast)
        #expect(state.offset(at: wayPast) == 0)
        #expect(!state.isFinished(at: wayPast))
    }

    @Test("an unmeasured script never claims to be finished")
    func unmeasured() {
        var state = TeleprompterState()
        state.load("something")
        let start = Date()
        state.play(now: start)
        // scrollDistance is 0 until the view measures it; clamping to it would
        // park the script at the top and report it done.
        #expect(!state.isFinished(at: start.addingTimeInterval(60)))
        #expect(state.progress(at: start.addingTimeInterval(60)) == 0)
    }

    // MARK: - Transport & modes

    @Test("restart rewinds without stopping, and edit goes back to the top, paused")
    func restartAndEdit() {
        var state = loaded()
        let start = Date()
        state.play(now: start)
        let later = start.addingTimeInterval(6)
        #expect(state.offset(at: later) > 0)

        state.restart(now: later)
        #expect(state.isRunning, "restart should not stop it")
        #expect(state.offset(at: later) == 0)

        state.edit()
        #expect(state.mode == .compose)
        #expect(!state.isRunning)
        #expect(state.offset() == 0)
        #expect(state.script == "line one\nline two\nline three", "editing lost the script")
    }

    @Test("an empty script cannot be played, and loading one rewinds")
    func emptyAndLoad() {
        var state = TeleprompterState()
        #expect(!state.hasScript)
        state.play()
        #expect(!state.isRunning, "an empty prompter started")

        state.load("   \n  ")
        #expect(!state.hasScript, "whitespace is not a script")

        var running = loaded()
        let start = Date()
        running.play(now: start)
        _ = running.offset(at: start.addingTimeInterval(5))
        running.pause(now: start.addingTimeInterval(5))
        running.load("a brand new script")
        #expect(running.offset() == 0, "a new script kept the old position")
        #expect(running.scrollDistance == 0, "a new script kept the old measurement")
        #expect(!running.isRunning)
    }

    // MARK: - Layout

    @Test("every control sits inside the bar, apart from the others, and hits itself")
    func controlLayout() {
        let placed = TeleprompterLayout.actions(in: frame)
        #expect(Set(placed.map(\.action)) == [.playPause, .restart, .slower, .faster, .edit, .close])

        for (index, item) in placed.enumerated() {
            #expect(frame.contains(item.rect), "\(item.action) outside the panel")
            let centre = CGPoint(x: item.rect.midX, y: item.rect.midY)
            #expect(TeleprompterLayout.action(at: centre, in: frame) == item.action)
            for other in placed[(index + 1)...] {
                #expect(!item.rect.intersects(other.rect), "\(item.action) overlaps \(other.action)")
            }
        }

        // The reading window sits above the bar and below the notch strip, so
        // no line is ever drawn behind the cutout or under a button.
        let reading = TeleprompterLayout.readingFrame(in: frame, notchInset: notchInset)
        #expect(reading.maxY <= frame.maxY - notchInset)
        #expect(reading.height > 0)
        for item in placed {
            #expect(!reading.intersects(item.rect), "the reading window overlaps \(item.action)")
        }

        // Clicking the text closes the prompter rather than hitting a control.
        #expect(TeleprompterLayout.action(at: CGPoint(x: reading.midX, y: reading.midY), in: frame) == nil)
    }

    @Test("the speed readout is drawn exactly between its two buttons")
    func speedReadoutPlacement() {
        let placed = TeleprompterLayout.actions(in: frame)
        let slower = placed.first { $0.action == .slower }!.rect
        let faster = placed.first { $0.action == .faster }!.rect
        let readout = TeleprompterLayout.speedRect(in: frame)
        #expect(readout.minX == slower.maxX + TeleprompterLayout.buttonSpacing)
        #expect(faster.minX == readout.maxX + TeleprompterLayout.buttonSpacing)
        // And the whole cluster is centred on the panel.
        #expect(abs(readout.midX - frame.midX) < 1)
    }
}
