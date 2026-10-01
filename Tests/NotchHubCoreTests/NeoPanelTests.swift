import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO panel")
struct NeoPanelTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 3_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test("opens when NEO starts answering, folds 5 s after it is quiet")
    func answerThenQuiet() {
        var panel = NeoPanelModel()
        panel.receive(state: .listening, at: t0)
        #expect(!panel.isOpen) // listening alone is the lane's
        panel.receive(state: .thinking, at: at(1))
        #expect(panel.isOpen)
        #expect(panel.nextWake(at: at(1)) == nil) // answering: nothing folds it
        panel.receive(state: .speaking, at: at(2))
        panel.receive(state: .idle, at: at(3))
        #expect(panel.isOpen)
        #expect(panel.nextWake(at: at(3)) == at(8))
        let ticked1 = panel.tick(at: at(7.9))
        #expect(!ticked1)
        #expect(panel.isOpen)
        let ticked2 = panel.tick(at: at(8))
        #expect(ticked2)
        #expect(!panel.isOpen)
        #expect(panel.nextWake(at: at(8)) == nil)
    }

    @Test("every answering state opens it; idle and listening do not")
    func answeringStates() {
        for state in NeoState.allCases {
            var panel = NeoPanelModel()
            panel.receive(state: state, at: t0)
            #expect(panel.isOpen == NeoPanelModel.answeringStates.contains(state), "\(state)")
        }
        #expect(NeoPanelModel.answeringStates == [.thinking, .working, .searching, .speaking, .confirming])
    }

    @Test("the mouse in it, a card, or a pin hold it open; leaving restarts the 5 s")
    func holds() {
        var panel = NeoPanelModel()
        panel.receive(state: .speaking, at: t0)
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
        pinned.receive(state: .thinking, at: t0)
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
        panel.receive(state: .idle, at: at(62))
        #expect(panel.nextWake(at: at(62)) == at(67))
        panel.toggle(at: at(63))
        #expect(!panel.isOpen)
    }

    @Test("closed while NEO is busy it stays closed for the rest of the turn")
    func dismissedUntilQuiet() {
        var panel = NeoPanelModel()
        panel.receive(state: .thinking, at: t0)
        panel.close(at: at(1)) // Esc
        #expect(!panel.isOpen)
        panel.receive(state: .searching, at: at(2))
        panel.receive(state: .speaking, at: at(3))
        #expect(!panel.isOpen)
        panel.card(.song, open: true, at: at(3.5))
        #expect(!panel.isOpen) // even a card of this turn
        panel.receive(state: .idle, at: at(4))
        panel.receive(state: .thinking, at: at(10)) // the next turn
        #expect(panel.isOpen)
    }

    @Test("the page asking to be seen opens it; the core going away closes everything")
    func showAndDisconnect() {
        var panel = NeoPanelModel()
        panel.show(at: t0)
        #expect(panel.isOpen && panel.isHeld)
        panel.card(.camera, open: true, at: at(1))
        panel.disconnected(at: at(2))
        #expect(!panel.isOpen && panel.cards.isEmpty && !panel.isHeld)
    }
}

@Suite("NEO panel layout")
struct NeoPanelLayoutTests {

    let screen = CGSize(width: 1728, height: 1117)

    @Test("the chat is 420×520; a request grows the page within the screen's limits")
    func sizes() {
        #expect(NeoPanelLayout.pageSize(requested: nil, screen: screen) == CGSize(width: 420, height: 520))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 100, height: 100), screen: screen) == CGSize(width: 420, height: 520))
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 847, height: 788), screen: screen) == CGSize(width: 847, height: 788))
        let max = NeoPanelLayout.maxPageSize(screen: screen)
        #expect(max.width == 1000 && abs(max.height - 1117 * 0.86) < 0.001)
        #expect(NeoPanelLayout.pageSize(requested: CGSize(width: 5000, height: 5000), screen: screen) == max)
    }

    @Test("the panel hangs from the notch, centred, the page below the notch strip")
    func frame() {
        let geometry = NotchGeometry.make(screenFrame: CGRect(origin: .zero, size: screen), safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0))
        var content = IslandContentSize.default
        let standard = geometry.frame(for: .neoPanel, content: content)
        #expect(standard.width == 420 && standard.height == 552)
        #expect(standard.midX == geometry.notchFrame.midX && standard.maxY == geometry.notchFrame.maxY)
        content.neoPanel = CGSize(width: 847, height: 788)
        let wide = geometry.frame(for: .neoPanel, content: content)
        #expect(wide.width == 847 && wide.height == 820)
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
