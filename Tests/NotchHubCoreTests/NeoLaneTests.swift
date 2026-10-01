import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO state hold")
struct NeoStateHoldTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("the first state applies at once; the next waits out the dwell")
    func dwell() {
        var hold = NeoStateHold()
        #expect(hold.receive(.listening, at: t0) == nil)
        #expect(hold.current == .listening)

        // 100 ms later: too soon. The change is due at 350 ms.
        let due = hold.receive(.thinking, at: t0.addingTimeInterval(0.1))
        #expect(due == t0.addingTimeInterval(0.35))
        #expect(hold.current == .listening)
        let notYet = hold.settle(at: t0.addingTimeInterval(0.2))
        #expect(!notYet)
        #expect(hold.current == .listening)
        let settled = hold.settle(at: t0.addingTimeInterval(0.35))
        #expect(settled)
        #expect(hold.current == .thinking)
        #expect(hold.pending == nil)
    }

    @Test("a flurry collapses into the last state, which shows once things settle")
    func flurry() {
        var hold = NeoStateHold()
        hold.receive(.speaking, at: t0)
        hold.receive(.listening, at: t0.addingTimeInterval(0.05))
        hold.receive(.speaking, at: t0.addingTimeInterval(0.10))
        hold.receive(.idle, at: t0.addingTimeInterval(0.15))
        #expect(hold.current == .speaking)
        #expect(hold.pending?.state == .idle)
        let settled = hold.settle(at: t0.addingTimeInterval(0.35))
        #expect(settled)
        #expect(hold.current == .idle)
    }

    @Test("after the dwell has passed, a new state applies immediately")
    func afterDwell() {
        var hold = NeoStateHold()
        hold.receive(.listening, at: t0)
        #expect(hold.receive(.speaking, at: t0.addingTimeInterval(0.5)) == nil)
        #expect(hold.current == .speaking)
    }
}

@Suite("NEO lane")
struct NeoLaneModelTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 2_000)

    private func connected(at now: Date) -> NeoLaneModel {
        var lane = NeoLaneModel()
        lane.receive(.connected(true), at: now)
        return lane
    }

    @Test("hidden while NEO is idle or away; out while it is busy")
    func visibility() {
        var lane = NeoLaneModel()
        #expect(lane.content(at: t0) == nil)
        lane.receive(.state(.listening), at: t0)
        // Not connected: a stale state from nowhere shows nothing.
        #expect(!lane.isShown(at: t0))

        lane = connected(at: t0)
        lane.receive(.state(.idle), at: t0)
        #expect(lane.content(at: t0) == nil)
        lane.receive(.state(.listening), at: t0.addingTimeInterval(1))
        #expect(lane.content(at: t0.addingTimeInterval(1)) == NeoLaneContent(state: .listening, line: "Listening…"))
    }

    @Test("what it hears while listening, what it says while speaking")
    func lines() {
        var lane = connected(at: t0)
        lane.receive(.state(.listening), at: t0)
        lane.receive(.transcript(role: .user, text: "what's the", final: false), at: t0.addingTimeInterval(0.1))
        lane.receive(.transcript(role: .user, text: "what's the weather", final: true), at: t0.addingTimeInterval(0.2))
        #expect(lane.content(at: t0.addingTimeInterval(0.2)) == NeoLaneContent(state: .listening, line: "what's the weather", isTranscript: true))

        lane.receive(.state(.thinking), at: t0.addingTimeInterval(1))
        #expect(lane.content(at: t0.addingTimeInterval(1)) == NeoLaneContent(state: .thinking, line: "Thinking…"))

        lane.receive(.state(.speaking), at: t0.addingTimeInterval(2))
        #expect(lane.content(at: t0.addingTimeInterval(2))?.line == "Speaking…")
        lane.receive(.transcript(role: .assistant, text: "Sunny and", final: false), at: t0.addingTimeInterval(2.1))
        lane.receive(.transcript(role: .assistant, text: "Sunny and 21°", final: true), at: t0.addingTimeInterval(2.2))
        #expect(lane.content(at: t0.addingTimeInterval(2.2)) == NeoLaneContent(state: .speaking, line: "Sunny and 21°", isTranscript: true))

        // A new listen starts with a clean line.
        lane.receive(.state(.listening), at: t0.addingTimeInterval(3))
        #expect(lane.content(at: t0.addingTimeInterval(3))?.line == "Listening…")
    }

    @Test("after idle the lane keeps the last reply for 1.2 s, then tucks in")
    func tuckIn() {
        var lane = connected(at: t0)
        lane.receive(.state(.speaking), at: t0)
        lane.receive(.transcript(role: .assistant, text: "Done.", final: true), at: t0.addingTimeInterval(0.1))
        let idleAt = t0.addingTimeInterval(1)
        let wake = lane.receive(.state(.idle), at: idleAt)
        #expect(wake == idleAt.addingTimeInterval(NeoLaneModel.hideDelay))
        #expect(lane.content(at: idleAt) == NeoLaneContent(state: .idle, line: "Done.", isTranscript: true))
        #expect(lane.content(at: idleAt.addingTimeInterval(1.19)) != nil)
        #expect(lane.content(at: idleAt.addingTimeInterval(1.2)) == nil)
        #expect(lane.nextWake(at: idleAt.addingTimeInterval(1.2)) == nil)

        // Something new before the delay is up keeps it out.
        var busy = lane
        busy.receive(.state(.listening), at: idleAt.addingTimeInterval(0.5))
        #expect(busy.content(at: idleAt.addingTimeInterval(1.5)) != nil)
    }

    @Test("the dwell holds the orb; the model says when to come back")
    func holdWakes() {
        var lane = connected(at: t0)
        lane.receive(.state(.listening), at: t0)
        let wake = lane.receive(.state(.thinking), at: t0.addingTimeInterval(0.1))
        #expect(wake == t0.addingTimeInterval(0.35))
        #expect(lane.content(at: t0.addingTimeInterval(0.2))?.state == .listening)
        let early = lane.tick(at: t0.addingTimeInterval(0.2))
        #expect(!early)
        let due = lane.tick(at: t0.addingTimeInterval(0.35))
        #expect(due)
        #expect(lane.content(at: t0.addingTimeInterval(0.35))?.state == .thinking)
    }

    @Test("a held idle still shows, and a quick idle→busy never tucks in")
    func heldIdle() {
        var lane = connected(at: t0)
        lane.receive(.state(.speaking), at: t0)
        lane.receive(.state(.idle), at: t0.addingTimeInterval(0.1))
        #expect(lane.isShown(at: t0.addingTimeInterval(0.2)))
        lane.receive(.state(.listening), at: t0.addingTimeInterval(0.2))
        lane.tick(at: t0.addingTimeInterval(0.35))
        #expect(lane.content(at: t0.addingTimeInterval(0.35))?.state == .listening)
        #expect(lane.isShown(at: t0.addingTimeInterval(5)))
    }

    @Test("a note replaces the line for a while; the core going away hides everything")
    func notesAndDisconnect() {
        var lane = connected(at: t0)
        lane.receive(.state(.searching), at: t0)
        let wake = lane.receive(.note("No results from the web."), at: t0.addingTimeInterval(0.5))
        #expect(wake == t0.addingTimeInterval(8.5))
        #expect(lane.content(at: t0.addingTimeInterval(1))?.line == "No results from the web.")
        let expired = lane.tick(at: t0.addingTimeInterval(8.5))
        #expect(expired)
        #expect(lane.content(at: t0.addingTimeInterval(8.5))?.line == "Searching…")

        lane.receive(.error("Mic blocked"), at: t0.addingTimeInterval(9))
        #expect(lane.content(at: t0.addingTimeInterval(9))?.line == "Mic blocked")

        lane.receive(.connected(false), at: t0.addingTimeInterval(10))
        #expect(lane.content(at: t0.addingTimeInterval(10)) == nil)
        #expect(lane.state == .idle)
    }

    @Test("each NEO state maps to its orb and label, as NEO's overlay does")
    func mapping() {
        #expect(NeoState.idle.orb == .breathing)
        #expect(NeoState.listening.orb == .listening)
        #expect(NeoState.thinking.orb == .solving)
        #expect(NeoState.working.orb == .solving)
        #expect(NeoState.searching.orb == .searching)
        #expect(NeoState.speaking.orb == .composing)
        #expect(NeoState.connecting.orb == .connecting)
        #expect(NeoState.confirming.orb == .shaping)
        #expect(NeoState.confirming.label == "Needs your OK")
    }
}

@Suite("NEO lane width")
struct NeoLaneLayoutTests {

    @Test("the orb fills the notch strip less its insets, never smaller than 16")
    func orbSize() {
        #expect(NeoLaneLayout.orbSize(notchHeight: 32) == 24)
        #expect(NeoLaneLayout.orbSize(notchHeight: 38) == 30)
        #expect(NeoLaneLayout.orbSize(notchHeight: 10) == 16)
    }

    @Test("the lane is content-driven: insets + orb + gap + a capped line")
    func width() {
        let orb = NeoLaneLayout.orbSize(notchHeight: 32)
        #expect(NeoLaneLayout.width(notchHeight: 32, textWidth: 0) == 12 + orb + 10)
        #expect(NeoLaneLayout.width(notchHeight: 32, textWidth: 60) == 12 + orb + 8 + 60 + 10)
        #expect(NeoLaneLayout.width(notchHeight: 32, textWidth: 1_000) == 12 + orb + 8 + NeoLaneLayout.maxTextWidth + 10)
        #expect(NeoLaneLayout.textWidth(notchHeight: 32, laneWidth: NeoLaneLayout.width(notchHeight: 32, textWidth: 60)) == 60)
    }

    private func geometry() -> NotchGeometry {
        NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryRight: CGRect(x: 856, y: 950, width: 656, height: 32)
        )
    }

    @Test("idle grows left by the lane and nothing else; without it idle is the notch")
    func idle() {
        let g = geometry()
        var content = IslandContentSize.default
        #expect(g.frame(for: .idle, content: content) == g.notchFrame)
        content.neoLead = 120
        let frame = g.frame(for: .idle, content: content)
        #expect(abs(frame.minX - (g.notchFrame.minX - 120)) < 0.001)
        #expect(abs(frame.maxX - g.notchFrame.maxX) < 0.001)
        #expect(frame.height == g.notchFrame.height)
    }

    @Test("the lane wins the left side from the pet's dock and leaves the right alone")
    func idleWithPet() {
        let g = geometry()
        var content = IslandContentSize.default
        content.petDock = .home
        content.neoLead = 120
        let frame = g.frame(for: .idle, content: content)
        #expect(abs(frame.minX - (g.notchFrame.minX - 120)) < 0.001)
        #expect(abs(frame.maxX - (g.notchFrame.maxX + PetDock.home.trail)) < 0.001)

        content.petDock = PetDock(side: .left, reach: PetLayout.idleDock)
        let left = g.frame(for: .idle, content: content)
        #expect(abs(left.minX - (g.notchFrame.minX - 120)) < 0.001)
        #expect(abs(left.maxX - g.notchFrame.maxX) < 0.001)
    }

    @Test("the wings and the compact bar add the lane to their lead side")
    func bars() {
        let g = geometry()
        var content = IslandContentSize(compactLead: 48, compactTrail: 110, wingSide: 90)
        content.wingLead = 60
        let plainWings = g.frame(for: .wings, content: content)
        let plainCompact = g.frame(for: .compact, content: content)
        content.neoLead = 100
        let wings = g.frame(for: .wings, content: content)
        let compact = g.frame(for: .compact, content: content)
        #expect(abs(wings.minX - (plainWings.minX - 100)) < 0.001)
        #expect(abs(wings.maxX - plainWings.maxX) < 0.001)
        #expect(abs(compact.minX - (plainCompact.minX - 100)) < 0.001)
        #expect(abs(compact.maxX - plainCompact.maxX) < 0.001)
        // The notch stays where it is: the lane and the lead content are both left of it.
        #expect(abs((compact.minX + 100 + 48) - g.notchFrame.minX) < 0.001)
    }

    @Test("the fixed surfaces keep their frames; the lane draws inside them")
    func panels() {
        let g = geometry()
        var content = IslandContentSize.default
        content.neoLead = 100
        #expect(g.frame(for: .expanded, content: content) == g.expandedFrame)
        #expect(g.frame(for: .interactive, content: content) == g.interactiveFrame)
    }

    @Test("the lane's motion is the island's own: a peek out, a collapse back")
    func motion() {
        let g = geometry()
        var content = IslandContentSize.default
        content.neoLead = 120
        let out = g.frame(for: .idle, content: content)
        #expect(IslandMotion.between(from: g.notchFrame, fromIdle: true, to: out, toIdle: true) == .peek)
        #expect(IslandMotion.between(from: out, fromIdle: true, to: g.notchFrame, toIdle: true) == .collapse)
    }
}
