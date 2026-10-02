import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO's Allow / Cancel under the notch")
struct NeoConfirmTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 9_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    let trash = NeoConfirmCard(actionID: "trash:4d15b0099e5a9d0a", tool: "trash", summary: "move report.pdf to the Trash", detail: "/Users/me/Documents/report.pdf")
    let shell = NeoConfirmCard(actionID: "shell:b7f034d65f0f4e1a", tool: "shell", summary: "run a command", detail: "mv a b")

    // MARK: - The model

    @Test("a confirmation brings the buttons up, over whatever the island shows — except NEO's own chat")
    func appears() {
        var model = NeoConfirmModel()
        #expect(!model.isShowing && model.card == nil)
        for state in IslandState.allCases { #expect(model.state(over: state) == state, "\(state)") }

        let appeared = model.receive(.confirm(trash), at: t0)
        #expect(appeared)
        #expect(model.isShowing && model.card == trash && model.shownAt == t0)
        // It outranks the idle island, every activity shape, a call's
        // controls and NotchHub's own panels (the camera among them).
        for state in IslandState.allCases where state != .neoPanel {
            #expect(model.state(over: state) == .neoConfirm, "\(state)")
        }
        // NEO's chat shows the page's own card: the buttons are not doubled.
        #expect(model.state(over: .neoPanel) == .neoPanel)
    }

    @Test("NEO's state alone brings up nothing: only a staged confirmation does")
    func stateIsNotAConfirmation() {
        var model = NeoConfirmModel()
        for fact: NeoFact in [.connected(true), .state(.confirming), .state(.speaking), .woke, .note("n"), .error("e"),
                              .transcript(role: .assistant, text: "Should I go ahead?", final: true), .card(.browser, open: true)] {
            let changed = model.receive(fact, at: t0)
            #expect(!changed, "\(fact)")
            #expect(!model.isShowing, "\(fact)")
        }
    }

    @Test("a newer confirmation replaces the one showing, and its guard starts afresh; the same card told again changes nothing")
    func replaced() {
        var model = NeoConfirmModel()
        model.receive(.confirm(trash), at: t0)
        #expect(model.mayAllow(at: at(1)))
        // The core supersedes the old card, then stages the new one.
        let superseded = model.receive(.confirmDone(trash.actionID), at: at(1))
        #expect(superseded && !model.isShowing)
        let next = model.receive(.confirm(shell), at: at(1))
        #expect(next && model.card == shell && model.shownAt == at(1))
        #expect(!model.mayAllow(at: at(1.5)) && model.mayAllow(at: at(1.6)))
        // …or just the new one, the old never called done.
        let straight = model.receive(.confirm(trash), at: at(2))
        #expect(straight && model.card == trash && model.shownAt == at(2))
        // The same card again (a reconnect's hello): still up since it came up.
        let again = model.receive(.confirm(trash), at: at(5))
        #expect(!again && model.shownAt == at(2))
    }

    @Test("confirm_done clears it — answered elsewhere, superseded or expired — and only for the card it names")
    func cleared() {
        var model = NeoConfirmModel()
        model.receive(.confirm(trash), at: t0)
        let other = model.receive(.confirmDone("mail:someone-elses"), at: at(1))
        #expect(!other && model.isShowing)
        let done = model.receive(.confirmDone(trash.actionID), at: at(2))
        #expect(done && !model.isShowing && model.card == nil && model.shownAt == nil)
        let lateAllow = model.answer(.allow, at: at(3))
        let lateCancel = model.answer(.cancel, at: at(3))
        #expect(lateAllow == nil && lateCancel == nil)

        // The core going away takes its question with it: nobody would hear the answer.
        model.receive(.confirm(shell), at: at(4))
        let gone = model.receive(.connected(false), at: at(5))
        #expect(gone && !model.isShowing)
    }

    @Test("not doubled with NEO's chat panel: the page shows its own card; the buttons come up when the panel closes")
    func notDoubled() {
        var model = NeoConfirmModel()
        let opened = model.chat(open: true, at: t0)
        #expect(!opened)
        model.receive(.confirm(trash), at: at(1)) // kept, but nothing new on the island
        #expect(model.card == trash && !model.isShowing && model.shownAt == nil)
        let hidden = model.answer(.allow, at: at(5)) // not the island's to answer while hidden
        #expect(hidden == nil)
        let closed = model.chat(open: false, at: at(6))
        #expect(closed && model.isShowing && model.shownAt == at(6))
        #expect(!model.mayAllow(at: at(6.5)) && model.mayAllow(at: at(6.6))) // the guard counts from when they came up
        // The user opens the chat by hand with the buttons up: they give way to the page's card.
        let reopened = model.chat(open: true, at: at(7))
        #expect(reopened && !model.isShowing && model.state(over: .neoPanel) == .neoPanel)
    }

    @Test("the page asking to be seen for a confirmation does not open the chat — in whichever order the two sockets deliver")
    func pageShowIsNotTheChat() {
        // The island's socket first: the card is up, the page's request is declined.
        var model = NeoConfirmModel()
        model.receive(.confirm(trash), at: t0)
        let declined = model.pageAsksToShow(at: at(0.1))
        #expect(!declined && model.isShowing)

        // The page's socket first: the chat opens for it, and folds when the card reaches the island.
        var late = NeoConfirmModel()
        let granted = late.pageAsksToShow(at: t0)
        #expect(granted)
        late.chat(open: true, at: t0)
        #expect(late.foldsChat(for: .confirm(trash), at: at(0.3)))
        #expect(!late.foldsChat(for: .state(.confirming), at: at(0.3)))
        #expect(!late.foldsChat(for: .confirm(trash), at: at(1.6))) // long after: the page wanted something else

        // A chat the user opened is theirs: it never folds for a card.
        var mine = NeoConfirmModel()
        _ = mine.pageAsksToShow(at: t0)
        mine.userOpenedChat()
        mine.chat(open: true, at: at(0.1))
        #expect(!mine.foldsChat(for: .confirm(trash), at: at(0.3)))
        // With no card waiting the page may ask (a login page, a question).
        var idle = NeoConfirmModel()
        let mayAsk = idle.pageAsksToShow(at: t0)
        #expect(mayAsk)
    }

    @Test("Allow counts only after the buttons have been up 0.6 s — by Return or by click; Cancel always")
    func guarded() {
        #expect(NeoConfirmModel.allowGuard == 0.6)
        var model = NeoConfirmModel()
        model.receive(.confirm(trash), at: t0)
        for early in [0.0, 0.2, 0.59] {
            #expect(!model.mayAllow(at: at(early)))
            let tooSoon = model.answer(.allow, at: at(early))
            #expect(tooSoon == nil, "\(early)")
            #expect(model.isShowing) // a guarded Allow changes nothing
        }
        let allowed = model.answer(.allow, at: at(0.6))
        #expect(allowed == NeoConfirmAnswer(actionID: trash.actionID, yes: true))
        #expect(!model.isShowing) // gone at once: the island springs back
        let twice = model.answer(.allow, at: at(0.7)) // and a second press sends nothing
        #expect(twice == nil)

        var cancelled = NeoConfirmModel()
        cancelled.receive(.confirm(shell), at: t0)
        let no = cancelled.answer(.cancel, at: t0)
        #expect(no == NeoConfirmAnswer(actionID: shell.actionID, yes: false))
        #expect(!cancelled.isShowing)
    }

    @Test("Return and Enter allow, Esc cancels; a key still repeating from before is nobody's choice")
    func keys() {
        #expect(NeoConfirmKey.choice(forKeyCode: 36) == .allow)
        #expect(NeoConfirmKey.choice(forKeyCode: 76) == .allow)
        #expect(NeoConfirmKey.choice(forKeyCode: 53) == .cancel)
        #expect(NeoConfirmKey.choice(forKeyCode: 49) == nil) // space
        #expect(NeoConfirmKey.choice(forKeyCode: 36, isRepeat: true) == nil)
        #expect(NeoConfirmKey.choice(forKeyCode: 53, isRepeat: true) == nil)
        // …but it is still the buttons' key: it goes no further.
        #expect(NeoConfirmKey.handles(keyCode: 36) && NeoConfirmKey.handles(keyCode: 76) && NeoConfirmKey.handles(keyCode: 53))
        #expect(!NeoConfirmKey.handles(keyCode: 49))
    }

    @Test("answered or over, the island is exactly the shape it was underneath")
    func returnsToWhatWasThere() {
        for underlying in IslandState.allCases where underlying != .neoPanel && underlying != .neoConfirm {
            var model = NeoConfirmModel()
            #expect(model.state(over: underlying) == underlying)
            model.receive(.confirm(trash), at: t0)
            #expect(model.state(over: underlying) == .neoConfirm)
            _ = model.answer(.cancel, at: at(1))
            #expect(model.state(over: underlying) == underlying, "\(underlying) after Cancel")
            model.receive(.confirm(shell), at: at(2))
            model.receive(.confirmDone(shell.actionID), at: at(3))
            #expect(model.state(over: underlying) == underlying, "\(underlying) after confirm_done")
        }
    }

    // MARK: - The card and its answer

    @Test("the answer is the command NEO's own page sends from its card")
    func command() {
        #expect(NeoConfirmAnswer(actionID: "trash:4d15b0099e5a9d0a", yes: true).command
            == #"{"cmd":"confirm","yes":true,"action_id":"trash:4d15b0099e5a9d0a"}"#)
        #expect(NeoConfirmAnswer(actionID: "shell:b7f0", yes: false).command
            == #"{"cmd":"confirm","yes":false,"action_id":"shell:b7f0"}"#)
        // An id is data: nothing in it breaks out of its string.
        let odd = NeoConfirmAnswer(actionID: #"x","yes":true,"y":"\"#, yes: false).command
        let parsed = try? JSONSerialization.jsonObject(with: Data(odd.utf8)) as? [String: Any]
        #expect(parsed?["yes"] as? Bool == false && parsed?["action_id"] as? String == #"x","yes":true,"y":"\"# && parsed?.count == 3)
    }

    @Test("the card: its id, its words as one plain line, never raw JSON; no id, no card")
    func card() {
        let payload: [String: Any] = [
            "action_id": "shell:b7f0", "tool": "shell", "summary": "run a command",
            "detail": "mv '/tmp/a b/c.txt' ~/.Trash/\n  && echo done", "scopes": ["task"], "app": "Finder",
        ]
        let card = NeoConfirmCard(payload: payload)
        #expect(card == NeoConfirmCard(actionID: "shell:b7f0", tool: "shell", summary: "run a command", detail: "mv '/tmp/a b/c.txt' ~/.Trash/ && echo done"))
        #expect(card?.announcement == "Neo needs your OK: run a command")
        #expect(NeoConfirmCard(payload: ["tool": "shell", "summary": "x"]) == nil)
        #expect(NeoConfirmCard(payload: ["action_id": "", "summary": "x"]) == nil)
        let long = NeoConfirmCard(payload: ["action_id": "a:1", "summary": String(repeating: "word ", count: 100)])
        #expect(long?.summary.count == NeoConfirmCard.maxSummary && long?.summary.hasSuffix("…") == true)
        #expect(NeoConfirmCard(actionID: "a:1").announcement == "Neo needs your OK")
        #expect(NeoConfirmChoice.allow.title == "Allow" && NeoConfirmChoice.cancel.title == "Cancel")
    }

    // MARK: - Layout and hit testing

    let geometry = NotchGeometry.make(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    )

    @Test("the surface is the notch's width plus the pet's dock each side, one 40-pt row under the notch — and nothing more")
    func surface() {
        let notch = geometry.notchFrame
        let frame = geometry.frame(for: .neoConfirm, content: .default)
        #expect(frame.width == notch.width + PetLayout.idleDock * 2)
        #expect(frame.height == notch.height + 40)
        #expect(frame.midX == notch.midX && frame.maxY == notch.maxY) // centred on the notch, hung from the top
        #expect(frame.width < notch.width * 1.5) // "the notch's width or a little wider"
        #expect(geometry.envelopeFrame.contains(frame))
        // It is far smaller than the chat it replaces.
        let chat = geometry.frame(for: .neoPanel, content: .default)
        #expect(frame.height < chat.height / 4 && frame.width < chat.width)
        // The content's measurements do not move it.
        var content = IslandContentSize.default
        content.neoPanel = CGSize(width: 900, height: 700)
        content.petDock = PetDock(side: .left, reach: 4)
        #expect(geometry.frame(for: .neoConfirm, content: content) == frame)
    }

    @Test("two buttons side by side fill the row: Allow then Cancel, inside the surface and below the notch")
    func buttons() {
        let frame = geometry.frame(for: .neoConfirm, content: .default)
        let notchInset = geometry.notchFrame.height
        let buttons = NeoConfirmLayout.buttons(in: frame, notchInset: notchInset)
        #expect(buttons.map(\.choice) == [.allow, .cancel])
        let (allow, cancel) = (buttons[0].rect, buttons[1].rect)
        #expect(allow.size == cancel.size && allow.height == 26)
        #expect(allow.minX == frame.minX + 12 && cancel.maxX == frame.maxX - 12)
        #expect(cancel.minX - allow.maxX == 8)
        #expect(allow.minY == cancel.minY)
        for rect in [allow, cancel] {
            #expect(frame.contains(rect))
            #expect(rect.maxY <= frame.maxY - notchInset) // never behind the notch
            #expect(rect.minY - frame.minY >= 8) // clear of the rounded bottom
        }
    }

    @Test("a click lands on the button under it, misses between and around them, and never on both")
    func hitTesting() {
        let frame = geometry.frame(for: .neoConfirm, content: .default)
        let notchInset = geometry.notchFrame.height
        let buttons = NeoConfirmLayout.buttons(in: frame, notchInset: notchInset)
        let (allow, cancel) = (buttons[0].rect, buttons[1].rect)
        func hit(_ x: CGFloat, _ y: CGFloat) -> NeoConfirmChoice? {
            NeoConfirmLayout.choice(at: CGPoint(x: x, y: y), in: frame, notchInset: notchInset)
        }
        #expect(hit(allow.midX, allow.midY) == .allow)
        #expect(hit(cancel.midX, cancel.midY) == .cancel)
        #expect(hit(allow.minX + 1, allow.minY + 1) == .allow && hit(cancel.maxX - 1, cancel.maxY - 1) == .cancel)
        // The gap between them belongs to neither; nor does the strip beside the notch (the fox).
        #expect(hit((allow.maxX + cancel.minX) / 2, allow.midY) == nil)
        #expect(hit(frame.maxX - 10, frame.maxY - 16) == nil)
        #expect(hit(frame.midX, frame.maxY - 10) == nil) // the notch itself
        #expect(hit(allow.midX, frame.minY + 1) == nil) // under the buttons
        // Every point is one button's at most.
        var x = frame.minX
        while x <= frame.maxX {
            let a = allow.insetBy(dx: -2, dy: -2).contains(CGPoint(x: x, y: allow.midY))
            let c = cancel.insetBy(dx: -2, dy: -2).contains(CGPoint(x: x, y: allow.midY))
            #expect(!(a && c))
            x += 0.5
        }
    }

    @Test("the fox keeps its place: beside the notch, exactly where it stands on the idle dock, on either side")
    func foxStays() {
        let notch = geometry.notchFrame
        let confirm = geometry.frame(for: .neoConfirm, content: .default)
        var docked = IslandContentSize.default
        for side in [PetSide.right, .left] {
            let dock = PetDock(side: side, reach: PetLayout.idleDock)
            docked.petDock = dock
            let idle = geometry.frame(for: .idle, content: docked)
            let atRest = PetLayout.placement(for: .idle, islandSize: idle.size, notchHeight: notch.height, dock: dock)
            let asking = PetLayout.placement(for: .neoConfirm, islandSize: confirm.size, notchHeight: notch.height, dock: dock)
            #expect(atRest != nil && asking != nil)
            if let atRest, let asking {
                #expect(idle.minX + atRest.origin.x == confirm.minX + asking.origin.x, "\(side)")
                #expect(atRest.origin.y == asking.origin.y && atRest.scale == asking.scale && atRest.anchor == asking.anchor)
                // In the strip, outside the notch — never behind it, never over the buttons.
                let x = confirm.minX + asking.origin.x
                #expect(x >= notch.maxX || x + asking.size <= notch.minX)
                #expect(asking.origin.y + asking.size <= notch.height)
            }
        }
        #expect(PetBrain.neoAnimation(for: .confirming) == .neoAsk) // its "!"
    }

    @Test("Ghost Mode hides the buttons with the island; they show nothing of NEO's that needs hiding otherwise")
    func ghost() {
        #expect(GhostMode.hidesFromCapture(state: .neoConfirm, ghostModeEnabled: true))
        #expect(!GhostMode.hidesFromCapture(state: .neoConfirm, ghostModeEnabled: false))
        #expect(GhostMode.reason(state: .neoConfirm, ghostModeEnabled: true) == .ghostMode)
    }

    @Test("the pop is a spring with a little bounce; under Reduce Motion a plain ease with none")
    func pop() {
        #expect(DesignTokens.confirmPop(reduceMotion: false) == .spring(response: 0.38, dampingFraction: 0.66, blendDuration: 0.12))
        #expect(DesignTokens.confirmPop(reduceMotion: true) == .easeOut(duration: 0.20))
        #expect(DesignTokens.confirmPop(reduceMotion: false) != DesignTokens.springExpand)
    }
}

@Suite("Where the island catches the mouse")
struct IslandHitRegionTests {

    let geometry = NotchGeometry.make(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    )

    @Test("the hit region is the surface's final frame from the moment it is presented: a still cursor's first click is the island's")
    func firstClick() {
        let notch = geometry.notchFrame
        var docked = IslandContentSize.default
        docked.petDock = .home
        let idle = IslandHitRegion(islandFrame: geometry.frame(for: .idle, content: docked), idleNotchFrame: notch, isIdle: true)
        for state in [IslandState.neoConfirm, .neoPanel] {
            let frame = geometry.frame(for: state, content: .default)
            // Where a button will be once the spring has settled — the cursor
            // is already there, and does not move.
            let cursor = state == .neoConfirm
                ? CGPoint(x: NeoConfirmLayout.buttons(in: frame, notchInset: notch.height)[0].rect.midX,
                          y: NeoConfirmLayout.buttons(in: frame, notchInset: notch.height)[0].rect.midY)
                : CGPoint(x: frame.midX, y: frame.minY + 20)
            // Before: nothing of the island is there; the window lets the click through.
            #expect(!idle.catchesMouse(at: cursor))
            #expect(idle.windowIgnoresMouse(cursorAt: cursor, interactive: false))
            // Presented: the region is the final frame at once — no hover event needed.
            let shown = IslandHitRegion(islandFrame: frame, idleNotchFrame: notch, isIdle: false)
            #expect(shown.catchesMouse(at: cursor), "\(state)")
            #expect(!shown.windowIgnoresMouse(cursorAt: cursor, interactive: false), "\(state)")
            #expect(shown.hoverRegion == frame.insetBy(dx: -8, dy: -8))
            // Every corner of the surface is the island's, and what lies beyond is not.
            for corner in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX - 0.5, y: frame.maxY - 0.5)] {
                #expect(shown.catchesMouse(at: corner))
            }
            #expect(!shown.catchesMouse(at: CGPoint(x: frame.minX - 40, y: frame.midY)))
            #expect(shown.windowIgnoresMouse(cursorAt: CGPoint(x: frame.minX - 40, y: frame.midY), interactive: false))
        }
    }

    @Test("idle, only the notch opens the island and only the pet takes the mouse; a panel with real controls never ignores it")
    func idleAndInteractive() {
        let notch = geometry.notchFrame
        var docked = IslandContentSize.default
        docked.petDock = .home
        let dock = geometry.frame(for: .idle, content: docked)
        let pet = CGRect(x: notch.maxX + 9, y: notch.minY + 8, width: 16, height: 16)
        let idle = IslandHitRegion(islandFrame: dock, idleNotchFrame: notch, idlePetFrame: pet, isIdle: true)
        let onPet = CGPoint(x: pet.midX, y: pet.midY)
        #expect(idle.catchesMouse(at: onPet) && !idle.opensIsland(at: CGPoint(x: pet.maxX + 2, y: pet.midY)))
        #expect(idle.isOverIdlePet(onPet))
        #expect(idle.opensIsland(at: CGPoint(x: notch.midX, y: notch.midY)))
        let below = CGPoint(x: notch.midX, y: notch.minY - 30)
        #expect(idle.windowIgnoresMouse(cursorAt: below, interactive: false))
        #expect(!idle.windowIgnoresMouse(cursorAt: below, interactive: true))
    }
}
