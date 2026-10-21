import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO panel")
struct NeoPanelTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 3_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test("a voice answer never opens it: listening, thinking, searching, speaking are the orb's alone")
    func answeringDoesNotOpen() {
        var panel = NeoPanelModel()
        panel.receive(state: .listening, at: t0)
        panel.receive(state: .thinking, at: at(1))
        panel.receive(state: .working, at: at(2))
        panel.receive(state: .searching, at: at(3))
        panel.receive(state: .speaking, at: at(4))
        #expect(!panel.isOpen)
        #expect(panel.nextWake(at: at(4)) == nil)
        panel.receive(state: .idle, at: at(5))
        #expect(!panel.isOpen)
        let ticked = panel.tick(at: at(60))
        #expect(!ticked && !panel.isOpen)
    }

    @Test("no state opens it on its own — NEO needing an OK is the island's Allow / Cancel, not the chat; an open panel is held through the question and folds 5 s after NEO is quiet")
    func confirmThenQuiet() {
        for state in NeoState.allCases {
            var panel = NeoPanelModel()
            panel.receive(state: state, at: t0)
            #expect(!panel.isOpen, "\(state)")
        }
        #expect(NeoPanelModel.openingStates.isEmpty)
        #expect(NeoPanelModel.answeringStates == [.thinking, .working, .searching, .speaking, .confirming])

        // A panel the user has open shows the page's own card, and waits with it.
        var panel = NeoPanelModel()
        panel.show(at: t0)
        panel.receive(state: .thinking, at: at(0.5))
        panel.receive(state: .confirming, at: at(1))
        #expect(panel.isOpen)
        #expect(panel.nextWake(at: at(1)) == nil) // NEO is waiting on the user: nothing folds it
        panel.receive(state: .working, at: at(2)) // the OK given: NEO carries on
        #expect(panel.isOpen && panel.isHeld) // held through the rest of the answer
        panel.receive(state: .speaking, at: at(3))
        panel.receive(state: .idle, at: at(4))
        #expect(panel.isOpen)
        #expect(panel.nextWake(at: at(4)) == at(9))
        let ticked1 = panel.tick(at: at(8.9))
        #expect(!ticked1)
        #expect(panel.isOpen)
        let ticked2 = panel.tick(at: at(9))
        #expect(ticked2)
        #expect(!panel.isOpen)
        #expect(panel.nextWake(at: at(9)) == nil)
    }

    @Test("Search Screen's card holds the panel open with no quiet fold, and close() lets it go")
    func lensCardHolds() {
        var panel = NeoPanelModel()
        panel.show(at: t0)
        panel.card(.lens, open: true, at: t0)
        #expect(panel.isOpen && panel.isHeld && panel.cards == [.lens])
        panel.receive(state: .idle, at: at(1))
        #expect(panel.nextWake(at: at(1)) == nil)
        let ticked = panel.tick(at: at(600))
        #expect(!ticked && panel.isOpen) // never folds by itself while the card is up
        panel.card(.lens, open: false, at: at(601))
        panel.close(at: at(601))
        #expect(!panel.isOpen && panel.cards.isEmpty)
        // A Continue in NEO keeps the panel, as the chat, until NEO is quiet again.
        var kept = NeoPanelModel()
        kept.show(at: t0)
        kept.card(.lens, open: true, at: t0)
        kept.card(.lens, open: false, at: at(1))
        kept.show(at: at(1))
        #expect(kept.isOpen && kept.cards.isEmpty)
    }

    @Test("a card opens it, and NEO speaking about it never folds it mid-reply")
    func cardOpens() {
        var panel = NeoPanelModel()
        panel.receive(state: .working, at: t0)
        #expect(!panel.isOpen)
        panel.card(.browser, open: true, at: at(1))
        #expect(panel.isOpen)
        panel.receive(state: .speaking, at: at(2))
        panel.card(.browser, open: false, at: at(3))
        #expect(panel.isOpen && panel.isHeld) // still speaking: held
        #expect(panel.nextWake(at: at(3)) == nil)
        panel.receive(state: .idle, at: at(4))
        #expect(panel.nextWake(at: at(4)) == at(9))
    }

    @Test("the mouse in it, a card, or a pin hold it open; leaving restarts the 5 s")
    func holds() {
        var panel = NeoPanelModel()
        panel.show(at: t0)
        panel.receive(state: .speaking, at: at(0.5)) // the hand hold is spent
        panel.receive(state: .idle, at: at(1))
        panel.hover(true, at: at(2))
        #expect(panel.nextWake(at: at(2)) == nil)
        let ticked3 = panel.tick(at: at(30))
        #expect(!ticked3)
        #expect(panel.isOpen)
        panel.hover(false, at: at(30))
        #expect(panel.nextWake(at: at(30)) == at(35))
        panel.tick(at: at(35))
        #expect(!panel.isOpen)

        var carded = NeoPanelModel()
        carded.card(.browser, open: true, at: t0)
        #expect(carded.isOpen)
        carded.receive(state: .idle, at: at(1))
        #expect(carded.nextWake(at: at(1)) == nil)
        carded.card(.browser, open: false, at: at(20))
        #expect(carded.nextWake(at: at(20)) == at(25))

        var pinned = NeoPanelModel()
        pinned.show(at: t0)
        pinned.receive(state: .speaking, at: at(0.5)) // NEO answers: the hand's hold is spent
        pinned.pin(true, at: at(1))
        pinned.receive(state: .idle, at: at(2))
        let ticked4 = pinned.tick(at: at(100))
        #expect(!ticked4)
        #expect(pinned.isOpen)
        pinned.pin(false, at: at(100))
        #expect(pinned.nextWake(at: at(100)) == at(105))
    }

    @Test("a click on the lane toggles it; by hand it stays until NEO answers again")
    func toggle() {
        var panel = NeoPanelModel()
        panel.toggle(at: t0)
        #expect(panel.isOpen)
        #expect(panel.nextWake(at: t0) == nil) // held by hand: no quiet clock
        let ticked5 = panel.tick(at: at(60))
        #expect(!ticked5)
        panel.receive(state: .thinking, at: at(61)) // NEO answers: the hold is spent
        #expect(panel.isOpen && panel.isHeld) // but never folds mid-answer
        panel.receive(state: .idle, at: at(62))
        #expect(panel.nextWake(at: at(62)) == at(67))
        panel.toggle(at: at(63))
        #expect(!panel.isOpen)
    }

    @Test("closed while NEO is busy it stays closed for the rest of the turn")
    func dismissedUntilQuiet() {
        var panel = NeoPanelModel()
        panel.show(at: t0)
        panel.receive(state: .working, at: at(0.5))
        panel.close(at: at(1)) // Esc
        #expect(!panel.isOpen)
        panel.receive(state: .searching, at: at(2))
        panel.receive(state: .confirming, at: at(3))
        #expect(!panel.isOpen)
        panel.card(.song, open: true, at: at(3.5))
        #expect(!panel.isOpen) // even a card of this turn
        panel.card(.song, open: false, at: at(3.8))
        panel.receive(state: .idle, at: at(4))
        panel.card(.browser, open: true, at: at(10)) // the next turn
        #expect(panel.isOpen)
    }

    @Test("the page asking to be seen opens it; the core going away drops the cards and holds, and the panel waits for it")
    func showAndDisconnect() {
        var panel = NeoPanelModel()
        panel.show(at: t0)
        #expect(panel.isOpen && panel.isHeld)
        panel.card(.camera, open: true, at: at(1))
        panel.pin(true, at: at(1))
        panel.disconnected(at: at(2))
        #expect(panel.isOpen && panel.cards.isEmpty && !panel.isHeld && !panel.isPinned && panel.isWaitingForCore)
        // Not the quiet delay: the grace, so a restart has time to come back.
        #expect(panel.nextWake(at: at(2)) == at(2 + NeoPanelModel.reconnectGrace))
        #expect(!panel.tick(at: at(2 + NeoPanelModel.idleCollapseDelay)) && panel.isOpen)
        #expect(panel.tick(at: at(2 + NeoPanelModel.reconnectGrace)) && !panel.isOpen && !panel.isWaitingForCore)
    }

    @Test("a core back within the grace leaves an ordinary open panel, which then folds after the quiet delay")
    func reconnectWithinGrace() {
        var panel = NeoPanelModel()
        panel.show(at: t0)
        panel.disconnected(at: at(1))
        panel.reconnected(at: at(4))
        #expect(panel.isOpen && !panel.isWaitingForCore)
        #expect(panel.nextWake(at: at(4)) == at(4 + NeoPanelModel.idleCollapseDelay))
        #expect(!panel.tick(at: at(4 + NeoPanelModel.idleCollapseDelay - 1)) && panel.isOpen)
        #expect(panel.tick(at: at(4 + NeoPanelModel.idleCollapseDelay)) && !panel.isOpen)
        // NEO answering on the way back holds it, as ever.
        panel.show(at: at(20))
        panel.disconnected(at: at(21))
        panel.reconnected(at: at(22))
        panel.receive(state: .speaking, at: at(22))
        #expect(panel.isHeld && panel.nextWake(at: at(22)) == nil)
    }

    @Test("the live sequence: a card opens it, NEO answers, the core restarts — the panel is still there when it is back")
    func liveRestart() {
        var panel = NeoPanelModel()
        panel.card(.browser, open: true, at: t0)
        panel.receive(state: .working, at: t0)
        panel.card(.browser, open: false, at: at(3))
        panel.receive(state: .idle, at: at(3))
        panel.receive(state: .thinking, at: at(4))
        panel.receive(state: .speaking, at: at(6))
        panel.receive(state: .idle, at: at(8))
        #expect(panel.isOpen)
        panel.tick(at: at(9))
        panel.disconnected(at: at(9.5))
        panel.receive(state: .idle, at: at(9.5))
        #expect(panel.isOpen && panel.isWaitingForCore)
        panel.tick(at: at(10))
        panel.reconnected(at: at(12.5))
        panel.receive(state: .idle, at: at(12.5))
        #expect(panel.isOpen && !panel.isWaitingForCore)
        #expect(!panel.tick(at: at(12.6)) && panel.isOpen)
        #expect(panel.nextWake(at: at(12.6)) == at(12.5 + NeoPanelModel.idleCollapseDelay))
    }

    @Test("a closed panel stays closed through a restart")
    func disconnectedWhileClosed() {
        var panel = NeoPanelModel()
        panel.disconnected(at: t0)
        #expect(!panel.isOpen && !panel.isWaitingForCore && panel.nextWake(at: t0) == nil)
        panel.reconnected(at: at(3))
        #expect(!panel.isOpen)
        // Closed by hand while waiting: that is the end of the wait.
        panel.show(at: at(4))
        panel.disconnected(at: at(5))
        panel.close(at: at(6))
        #expect(!panel.isOpen && !panel.isWaitingForCore && panel.nextWake(at: at(6)) == nil)
    }
}

@Suite("NEO panel layout")
struct NeoPanelLayoutTests {

    let screen = CGSize(width: 1728, height: 1117)

    @Test("the chat is compact, 340×300; a request grows the page within the screen's limits")
    func sizes() {
        #expect(NeoPanelLayout.standard == CGSize(width: 340, height: 300))
        #expect(NeoPanelLayout.pageSize(requested: nil, screen: screen) == CGSize(width: 340, height: 300))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 100, height: 100), screen: screen) == CGSize(width: 340, height: 300))
        // The camera or song card asks a little taller; the browser card asks most of the screen.
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 340, height: 440), screen: screen) == CGSize(width: 340, height: 440))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 760, height: 591), screen: screen) == CGSize(width: 760, height: 591))
        let max = NeoPanelLayout.maxPageSize(screen: screen)
        #expect(max.width == 1000 && abs(max.height - 1117 * 0.7) < 0.001)
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 5000, height: 5000), screen: screen) == max)
    }

    @Test("Search Screen's card may be shorter than the chat, only while it is open; the chat's minimum is unchanged")
    func lensMinimum() {
        let macbook = CGSize(width: 1512, height: 982)
        #expect(NeoPanelLayout.lensMinimum == CGSize(width: 340, height: 160))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 372, height: 200), screen: macbook, minimum: NeoPanelLayout.lensMinimum) == CGSize(width: 372, height: 200))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 372, height: 120), screen: macbook, minimum: NeoPanelLayout.lensMinimum) == CGSize(width: 372, height: 160))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 372, height: 200), screen: macbook) == CGSize(width: 372, height: 300))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 372, height: 900), screen: macbook, minimum: NeoPanelLayout.lensMinimum).height < 700)
        let geometry = NotchGeometry.make(screenFrame: CGRect(origin: .zero, size: macbook), safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0))
        var content = IslandContentSize.default
        content.neoPanel = CGSize(width: 372, height: 200)
        #expect(geometry.frame(for: .neoPanel, content: content).size == CGSize(width: 372, height: 332))
        content.neoPanelMinimum = NeoPanelLayout.lensMinimum
        #expect(geometry.frame(for: .neoPanel, content: content).size == CGSize(width: 372, height: 232))
    }

    @Test("on the 1512×982 MacBook screen the browser card has 60%×70%; a huge screen is capped")
    func screens() {
        let macbook = NeoPanelLayout.maxPageSize(screen: CGSize(width: 1512, height: 982))
        #expect(abs(macbook.width - 907.2) < 0.001 && abs(macbook.height - 687.4) < 0.001)
        #expect(NeoPanelLayout.maxPageSize(screen: CGSize(width: 2880, height: 1620)) == CGSize(width: 1000, height: 800))
        // A tiny screen still gives the chat its compact size, never less.
        #expect(NeoPanelLayout.maxPageSize(screen: CGSize(width: 400, height: 300)) == NeoPanelLayout.standard)
    }

    @Test("the panel hangs from the notch, centred, the page below the notch strip")
    func frame() {
        let geometry = NotchGeometry.make(screenFrame: CGRect(origin: .zero, size: screen), safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0))
        var content = IslandContentSize.default
        let standard = geometry.frame(for: .neoPanel, content: content)
        #expect(standard.width == 340 && standard.height == 332)
        #expect(standard.midX == geometry.notchFrame.midX && standard.maxY == geometry.notchFrame.maxY)
        content.neoPanel = CGSize(width: 760, height: 591)
        let wide = geometry.frame(for: .neoPanel, content: content)
        #expect(wide.width == 760 && wide.height == 623)
        // The window envelope holds the panel at its largest.
        content.neoPanel = NeoPanelLayout.maxPageSize(screen: screen)
        #expect(geometry.envelopeFrame.contains(geometry.frame(for: .neoPanel, content: content)))
    }

    @Test("NEO's panel is never shown to screen capture, as NEO's own window is not")
    func ghost() {
        #expect(GhostMode.hidesFromCapture(state: .neoPanel, ghostModeEnabled: false))
        #expect(GhostMode.reason(state: .neoPanel, ghostModeEnabled: false) == .alwaysPrivateSurface)
    }
}

@Suite("NEO host messages")
struct NeoHostMessageTests {

    @Test("the page's messages parse; anything else is nil, never a crash")
    func parse() {
        #expect(NeoHostMessage.parse(["type": "show"]) == .show)
        #expect(NeoHostMessage.parse(["type": "collapse"]) == .collapse)
        #expect(NeoHostMessage.parse(["type": "focus"]) == .focus)
        #expect(NeoHostMessage.parse(["type": "pin", "on": true]) == .pin(true))
        #expect(NeoHostMessage.parse(["type": "size", "w": 420, "h": 520.4]) == .size(CGSize(width: 420, height: 520.4)))
        #expect(NeoHostMessage.parse(["type": "clipboard", "text": "hi"]) == .clipboard("hi"))
        #expect(NeoHostMessage.parse(["type": "open_url", "url": "https://example.com/x"]) == .openURL(URL(string: "https://example.com/x")!))
        // Only web links leave the island.
        #expect(NeoHostMessage.parse(["type": "open_url", "url": "file:///etc/passwd"]) == nil)
        #expect(NeoHostMessage.parse(["type": "open_url", "url": "javascript:alert(1)"]) == nil)
        #expect(NeoHostMessage.parse(["type": "size", "w": -1, "h": 10]) == nil)
        #expect(NeoHostMessage.parse(["type": "size", "w": 1e9, "h": 10]) == nil)
        #expect(NeoHostMessage.parse(["type": "pin"]) == nil)
        #expect(NeoHostMessage.parse(["type": "dance"]) == nil)
        #expect(NeoHostMessage.parse("show") == nil)
        #expect(NeoHostMessage.parse(42) == nil)
    }
}
