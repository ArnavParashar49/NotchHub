import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO's Search Screen card")
struct NeoLensCardTests {

    let cid = String(repeating: "ab12", count: 8)
    let other = String(repeating: "cd34", count: 8)

    @Test("offered: shown at once, the panel opens openDelay later — and only for the card still offered")
    func offerThenOpen() {
        var model = NeoLensCardModel()
        #expect(NeoLensCardModel.openDelay == 0.24)
        #expect(model.receive(cid: cid, open: true, why: "", canShow: true) == .offer(cid))
        #expect(model.cid == cid && !model.isOpen)
        #expect(model.due(cid: cid) == .open(cid))
        #expect(model.isOpen)
        #expect(model.due(cid: cid) == .none) // (once)
        // Closed by the core before its panel opened: nothing opens later.
        var early = NeoLensCardModel()
        _ = early.receive(cid: cid, open: true, why: "", canShow: true)
        #expect(early.receive(cid: cid, open: false, why: "timeout", canShow: true) == .close(fold: false))
        #expect(early.due(cid: cid) == .none && early.cid == nil)
    }

    @Test("it can't show (the camera has the island, Allow / Cancel are up): refused, and never adopted")
    func refuse() {
        var model = NeoLensCardModel()
        #expect(model.receive(cid: cid, open: true, why: "", canShow: false) == .refuse(cid))
        #expect(model.cid == nil)
        #expect(model.due(cid: cid) == .none)
        #expect(model.receive(cid: cid, open: false, why: "unshown", canShow: true) == .none)
    }

    @Test("it shows only with NEO's page, no other panel on the island, and no question waiting for an OK")
    func canShow() {
        #expect(NeoLensCardModel.canShow(neoOn: true, hasPage: true, panelFree: true, confirmWaiting: false))
        // A question of NEO's waiting — under Allow / Cancel, or on the open chat: the card would hide it.
        #expect(!NeoLensCardModel.canShow(neoOn: true, hasPage: true, panelFree: true, confirmWaiting: true))
        // The teleprompter, the camera mirror, a file drop, Settings, the Tray, the pet's or NEO's camera panel.
        #expect(!NeoLensCardModel.canShow(neoOn: true, hasPage: true, panelFree: false, confirmWaiting: false))
        #expect(!NeoLensCardModel.canShow(neoOn: false, hasPage: true, panelFree: true, confirmWaiting: false))
        #expect(!NeoLensCardModel.canShow(neoOn: true, hasPage: false, panelFree: true, confirmWaiting: false))
        var model = NeoLensCardModel()
        let can = NeoLensCardModel.canShow(neoOn: true, hasPage: true, panelFree: true, confirmWaiting: true)
        #expect(model.receive(cid: cid, open: true, why: "", canShow: can) == .refuse(cid))
    }

    @Test("the core closes it: the panel folds — but stays, as the chat, for Continue in NEO and a chat turn")
    func closeFoldOrKeep() {
        #expect(NeoLensCardModel.keepsPanel == ["continue", "chat"])
        for (why, fold) in [("action", true), ("esc", true), ("x", true), ("idle", true), ("replaced", true), ("stop", true),
                            ("continue", false), ("chat", false)] {
            var model = NeoLensCardModel()
            _ = model.receive(cid: cid, open: true, why: "", canShow: true)
            _ = model.due(cid: cid)
            #expect(model.receive(cid: cid, open: false, why: why, canShow: true) == .close(fold: fold), "\(why)")
            #expect(model.cid == nil && !model.isOpen)
        }
    }

    @Test("the panel folding closes the card it showed, once; a card not yet open is not closed by it")
    func panelFolded() {
        var model = NeoLensCardModel()
        _ = model.receive(cid: cid, open: true, why: "", canShow: true)
        #expect(model.panelFolded() == nil) // (not open yet: the chat folding isn't the card's)
        _ = model.due(cid: cid)
        #expect(model.panelFolded() == cid)
        #expect(model.panelFolded() == nil)
        #expect(model.receive(cid: cid, open: false, why: "fold", canShow: true) == .none) // (the core's echo)
    }

    @Test("an older card's close is ignored; a newer card replaces it; a disconnect forgets it")
    func staleAndDisconnect() {
        var model = NeoLensCardModel()
        _ = model.receive(cid: cid, open: true, why: "", canShow: true)
        _ = model.due(cid: cid)
        #expect(model.receive(cid: other, open: false, why: "fold", canShow: true) == .none)
        #expect(model.cid == cid && model.isOpen)
        #expect(model.receive(cid: other, open: true, why: "", canShow: true) == .offer(other))
        #expect(model.cid == other && !model.isOpen)
        #expect(model.due(cid: cid) == .none)
        model.disconnected()
        #expect(model.cid == nil && !model.isOpen)
        #expect(model.due(cid: other) == .none)
        var gone = NeoLensCardModel()
        _ = gone.receive(cid: cid, open: true, why: "", canShow: true)
        gone.dropped(cid: other)
        #expect(gone.cid == cid)
        gone.dropped(cid: cid)
        #expect(gone.cid == nil)
    }
}
