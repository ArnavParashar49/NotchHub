import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO state hold")
struct NeoStateHoldTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("the first state applies at once; the next waits out the dwell (350 ms)")
    func dwell() {
        var hold = NeoStateHold()
        #expect(hold.receive(.listening, at: t0) == nil)
        #expect(hold.current == .listening)
        let due = hold.receive(.thinking, at: t0.addingTimeInterval(0.1))
        #expect(due == t0.addingTimeInterval(0.35))
        #expect(hold.current == .listening)
        let notYet = hold.settle(at: t0.addingTimeInterval(0.2))
        #expect(!notYet)
        let settled = hold.settle(at: t0.addingTimeInterval(0.35))
        #expect(settled)
        #expect(hold.current == .thinking && hold.pending == nil)
    }

    @Test("a flurry collapses into the last state, which shows once things settle")
    func flurry() {
        var hold = NeoStateHold()
        hold.receive(.speaking, at: t0)
        hold.receive(.listening, at: t0.addingTimeInterval(0.05))
        hold.receive(.speaking, at: t0.addingTimeInterval(0.10))
        hold.receive(.idle, at: t0.addingTimeInterval(0.15))
        #expect(hold.current == .speaking && hold.pending?.state == .idle)
        let settled = hold.settle(at: t0.addingTimeInterval(0.35))
        #expect(settled && hold.current == .idle)
    }
}

@Suite("NEO presence")
struct NeoPresenceTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 2_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func connected() -> NeoPresenceModel {
        var neo = NeoPresenceModel()
        neo.receive(.connected(true), at: t0)
        return neo
    }

    @Test("away or ready, NEO is not active; busy, it is — and for 1.2 s after")
    func active() {
        var neo = NeoPresenceModel()
        neo.receive(.state(.listening), at: t0)
        #expect(!neo.isActive(at: t0) && neo.state == .idle) // not connected: a state from nowhere
        neo = connected()
        neo.receive(.state(.idle), at: t0)
        #expect(!neo.isActive(at: t0) && neo.nextWake(at: t0) == nil)
        neo.receive(.state(.listening), at: at(1))
        #expect(neo.isActive(at: at(1)) && neo.state == .listening)
        neo.receive(.state(.speaking), at: at(2))
        neo.receive(.state(.idle), at: at(3))
        #expect(neo.state == .idle)
        #expect(neo.isActive(at: at(4.1)))
        #expect(neo.nextWake(at: at(3)) == at(4.2))
        let settled = neo.tick(at: at(4.2))
        #expect(settled && !neo.isActive(at: at(4.2)))
    }

    @Test("the dwell holds the state; the model says when to come back")
    func holdWakes() {
        var neo = connected()
        neo.receive(.state(.listening), at: t0)
        let wake = neo.receive(.state(.thinking), at: at(0.1))
        #expect(wake == at(0.35))
        #expect(neo.state == .listening)
        let early = neo.tick(at: at(0.2))
        #expect(!early)
        let due = neo.tick(at: at(0.35))
        #expect(due && neo.state == .thinking)
    }

    @Test("a quick idle→busy never settles; the core going away ends everything")
    func quickAndDisconnect() {
        var neo = connected()
        neo.receive(.state(.speaking), at: t0)
        neo.receive(.state(.idle), at: at(0.1))
        neo.receive(.state(.listening), at: at(0.2))
        neo.tick(at: at(0.35))
        #expect(neo.state == .listening && neo.isActive(at: at(5)))
        neo.receive(.connected(false), at: at(6))
        #expect(!neo.isActive(at: at(6)) && neo.state == .idle && !neo.isConnected)
    }

    @Test("transcripts, notes, cards and wakes are the panel's: the presence does not stir")
    func panelFacts() {
        var neo = connected()
        neo.receive(.state(.idle), at: t0)
        #expect(neo.receive(.transcript(role: .user, text: "hi", final: true), at: t0) == nil)
        #expect(neo.receive(.note("n"), at: t0) == nil)
        #expect(neo.receive(.card(.browser, open: true), at: t0) == nil)
        #expect(neo.receive(.woke, at: t0) == nil)
        #expect(!neo.isActive(at: t0))
    }
}

@Suite("NEO absent: the island is as it was")
struct NeoAbsentTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 3_000)
    let geometry = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0))

    @Test("no core: nothing is active, however long it waits; a core that is up and idle is the same")
    func nothing() {
        var neo = NeoPresenceModel()
        #expect(!neo.isActive(at: t0) && neo.nextWake(at: t0) == nil)
        let ticked = neo.tick(at: t0.addingTimeInterval(3_600))
        #expect(!ticked)
        neo.receive(.connected(true), at: t0)
        neo.receive(.state(.idle), at: t0)
        #expect(!neo.isActive(at: t0) && neo.nextWake(at: t0) == nil)
    }

    @Test("no core: the panel never opens on its own — not on hover, not on time")
    func noPanel() {
        var panel = NeoPanelModel()
        panel.hover(true, at: t0)
        panel.hover(false, at: t0.addingTimeInterval(1))
        panel.receive(state: .idle, at: t0.addingTimeInterval(2))
        panel.receive(state: .listening, at: t0.addingTimeInterval(3))
        let ticked = panel.tick(at: t0.addingTimeInterval(3_600))
        #expect(!ticked && !panel.isOpen && panel.nextWake(at: t0) == nil)
    }

    @Test("every island shape has exactly its pre-NEO frame — a pose is not a size; only the word \"Listening\" adds room, for its 1.5 s (NeoListeningTests)")
    func frames() {
        let content = IslandContentSize.default
        #expect(content.neoPanel == nil && content.listeningSlot == 0)
        #expect(geometry.frame(for: .idle, content: content) == geometry.notchFrame)
        #expect(geometry.frame(for: .wings, content: content) == geometry.wingsBar(sideWidth: NotchGeometry.wingWidth))
        #expect(geometry.frame(for: .compact, content: content) == geometry.compactFrame)
        #expect(geometry.frame(for: .expanded, content: content) == geometry.expandedFrame)
        #expect(geometry.frame(for: .interactive, content: content) == geometry.interactiveFrame)
        #expect(geometry.frame(for: .tray, content: content) == geometry.trayFrame)
        #expect(geometry.frame(for: .settings, content: content) == geometry.settingsFrame)
        #expect(geometry.frame(for: .skin, content: content) == geometry.skinFrame)
        #expect(geometry.frame(for: .meeting, content: content) == geometry.meetingFrame)
        #expect(geometry.frame(for: .fileDrop, content: content) == geometry.fileDropFrame)
        #expect(geometry.frame(for: .teleprompter, content: content) == geometry.teleprompterFrame)
        #expect(geometry.frame(for: .camera, content: content) == geometry.cameraFrame(expanded: false))
        // The pet's idle dock is the pet's — NEO busy or not, it is the same dock.
        var pet = content
        pet.petDock = .home
        #expect(geometry.frame(for: .idle, content: pet) == geometry.compactBar(lead: 0, trail: PetLayout.idleDock))
        // Nothing in the content size speaks of NEO but its panel's page size,
        // and that moves only NEO's own shape.
        var neo = content
        neo.neoPanel = CGSize(width: 900, height: 900)
        for state in IslandState.allCases where state != .neoPanel {
            #expect(geometry.frame(for: state, content: neo) == geometry.frame(for: state, content: content), "\(state)")
        }
    }

    @Test("Ghost Mode and capture are exactly as before for every pre-NEO shape")
    func ghost() {
        for state in IslandState.allCases where state != .neoPanel {
            let before: Set<IslandState> = [.teleprompter, .teleprompterCompose, .camera, .cameraExpanded]
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: false) == before.contains(state), "\(state)")
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: true))
        }
    }
}

@Suite("A click on the island while NEO is active")
struct NeoIslandClickTests {

    @Test("NEO active: a click anywhere opens the chat; idle: clicks are the island's own")
    func clicks() {
        #expect(NeoIslandClick.outcome(neoActive: true, panelOpen: false, otherPanel: false) == .open)
        #expect(NeoIslandClick.outcome(neoActive: false, panelOpen: false, otherPanel: false) == .none)
        // Another surface (settings, the Tray, the pet's panel) keeps its controls.
        #expect(NeoIslandClick.outcome(neoActive: true, panelOpen: false, otherPanel: true) == .none)
        // The open panel is the page's.
        #expect(NeoIslandClick.outcome(neoActive: true, panelOpen: true, otherPanel: false) == .none)
    }

    @Test("NEO's panel draws no pet: the chat's own orb is the only NEO on screen there")
    func noPetOnThePanel() {
        #expect(PetLayout.placement(for: .neoPanel, islandSize: CGSize(width: 420, height: 552), notchHeight: 32) == nil)
        #expect(PetLayout.placement(for: .idle, islandSize: CGSize(width: 219, height: 32), notchHeight: 32) != nil)
    }
}
