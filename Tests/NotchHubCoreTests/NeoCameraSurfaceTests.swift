import Foundation
import Testing
@testable import NotchHubCore

/// NEO's camera in the notch: only NEO opening its camera opens the panel,
/// and a session the user let go of never comes back by itself.
@Suite("NEO's camera surface")
struct NeoCameraSurfaceTests {

    private func state(_ sid: String, _ status: String, answer: String? = nil, labels: [String] = []) -> NeoFact {
        .cameraCard(NeoCameraCardState(sid: sid, status: status, answer: answer, labels: labels))
    }

    /// `camera_open` as the listener relays it: the session's first state,
    /// then its opening. Returns the surface with the panel showing.
    private func opened(_ sid: String = "cam-1") -> NeoCameraSurface {
        var surface = NeoCameraSurface()
        #expect(surface.receive(state(sid, "starting"), showing: false) == .none)
        #expect(surface.receive(.card(.camera, open: true), showing: false) == .open)
        #expect(surface.receive(state(sid, "live", labels: ["person"]), showing: true) == .update(refresh: true))
        #expect(surface.card?.sid == sid)
        return surface
    }

    @Test("a state is news for the panel that shows it, and never opens one")
    func stateNeverOpens() {
        var surface = NeoCameraSurface()
        for status in ["starting", "live", "analysing", "answered", "off"] {
            #expect(surface.receive(state("cam-1", status), showing: false) == .none, "\(status)")
        }
        // While it shows: a change of words redraws it; boxes alone do not.
        var showing = opened()
        #expect(showing.receive(state("cam-1", "live", labels: ["person"]), showing: true) == .update(refresh: false))
        #expect(showing.receive(state("cam-1", "answered", answer: "a mug", labels: ["person"]), showing: true) == .update(refresh: true))
        #expect(showing.card?.answer == "a mug")
    }

    /// NEO's answer to the user's stop, as it really arrives: its `off`,
    /// then its close.
    @Test("after the ×, the Tray, Settings or NEO's chat, NEO's off → close never brings the camera back",
          arguments: ["the ×", "the Tray", "Settings", "NEO's chat"])
    func offThenCloseAfterLettingGo(_ what: String) {
        var surface = opened()
        // The panel lets go of the camera (the × closes the island; the
        // others take it): the session to stop, by name.
        #expect(surface.release() == "cam-1", "\(what)")
        #expect(surface.released == "cam-1" && surface.card == nil)
        // A late live state, NEO's off, then its close: nothing for the island.
        #expect(surface.receive(state("cam-1", "live"), showing: false) == .none)
        #expect(surface.receive(state("cam-1", "off"), showing: false) == .none)
        #expect(surface.receive(.card(.camera, open: false), showing: false) == .none)
        #expect(surface.card == nil)
        // The session is over: nothing left to ignore.
        #expect(surface.released == nil)
    }

    @Test("NEO closing its own camera closes the panel once, and leaves nothing to stop")
    func neoClosesItsOwn() {
        var surface = opened()
        #expect(surface.receive(state("cam-1", "off"), showing: true) == .update(refresh: true))
        #expect(surface.receive(.card(.camera, open: false), showing: true) == .close)
        #expect(surface.card == nil)
        // The panel closing after it lets go of nothing.
        #expect(surface.release() == nil)
    }

    @Test("a new camera after one the user closed opens as usual")
    func newSessionAfterRelease() {
        var surface = opened("cam-1")
        _ = surface.release()
        _ = surface.receive(state("cam-1", "off"), showing: false)
        _ = surface.receive(.card(.camera, open: false), showing: false)
        #expect(surface.receive(state("cam-2", "starting"), showing: false) == .none)
        #expect(surface.receive(.card(.camera, open: true), showing: false) == .open)
        #expect(surface.receive(state("cam-2", "live"), showing: true) == .update(refresh: true))
        #expect(surface.card?.sid == "cam-2")
    }

    @Test("a close for an older session never closes a newer one")
    func staleClose() {
        var surface = opened("cam-1")
        _ = surface.release()
        // NEO opened another before the first one's close arrived.
        _ = surface.receive(state("cam-2", "starting"), showing: false)
        #expect(surface.receive(.card(.camera, open: true), showing: false) == .open)
        #expect(surface.receive(state("cam-2", "live"), showing: true) == .update(refresh: true))
        // The old one's off is ignored, and so is its close.
        #expect(surface.receive(state("cam-1", "off"), showing: true) == .none)
        #expect(surface.receive(.card(.camera, open: false), showing: true) == .none)
        #expect(surface.card?.sid == "cam-2")
    }

    @Test("a camera that is on when NotchHub connects (the hello's camera.live) opens with its state")
    func helloRecovers() {
        var surface = NeoCameraSurface()
        #expect(surface.receive(state("cam-1", "analysing", labels: ["mug"]), showing: false) == .none)
        #expect(surface.receive(.card(.camera, open: true), showing: false) == .open)
        // The opening shows what the hello said.
        #expect(surface.card == NeoCameraCardState(sid: "cam-1", status: "analysing", labels: ["mug"]))
    }

    @Test("a session the user closed, still live in a hello, is stopped again rather than shown again")
    func helloAfterLostStop() {
        var surface = opened()
        #expect(surface.release() == "cam-1")
        // The stop never reached the core: its hello still lists the camera.
        #expect(surface.receive(state("cam-1", "live"), showing: false) == .none)
        #expect(surface.receive(.card(.camera, open: true), showing: false) == .stop("cam-1"))
        #expect(surface.card == nil)
    }

    @Test("the core going away is not the user's close: the hello after a reconnect brings a live camera back")
    func disconnectForgetsTheRelease() {
        var surface = opened()
        // The app closes the panel as the core goes (its stop cannot be sent)…
        _ = surface.release()
        #expect(surface.receive(.connected(false), showing: false) == .none)
        #expect(surface.released == nil && surface.card == nil)
        // …and the camera is still on when the core is back.
        #expect(surface.receive(state("cam-1", "live"), showing: false) == .none)
        #expect(surface.receive(.card(.camera, open: true), showing: false) == .open)
    }

    @Test("facts that are not the camera's are nothing to it")
    func otherFacts() {
        var surface = opened()
        let before = surface
        for fact: NeoFact in [.state(.listening), .card(.browser, open: true), .card(.song, open: false), .woke,
                              .connected(true), .cameraFrame(Data([1, 2, 3])), .note("n")] {
            #expect(surface.receive(fact, showing: true) == .none)
        }
        #expect(surface == before)
    }
}
