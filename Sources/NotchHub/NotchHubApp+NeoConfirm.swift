import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// NEO needs an OK: Allow and Cancel under the notch.
///
/// When NEO stages a confirmation its core says so (`confirm`, or the one
/// still pending in its `hello`), whichever way the request came — typed,
/// through the agent, or a tool Gemini Live called itself, where NEO's state
/// never becomes `confirming` and nothing used to show at all. The island
/// then drops just far enough under the notch for two buttons
/// (`NeoConfirmModel`, `NeoConfirmLayout`, `NeoConfirmView`), with one
/// spring "pop", and the fox holds its "!" beside the notch.
///
/// **It outranks everything** the island shows — the idle island, an
/// activity, the dashboard, a call's controls, NotchHub's own panels (the
/// camera preview among them: its session keeps running untouched and the
/// picture is back the moment the question is answered). The one exception
/// is NEO's own chat panel: there the page shows its confirm card, and the
/// buttons are not drawn twice. The buttons are drawn OVER the island's
/// state, never in its place — `currentIslandState` puts them on top of
/// `underlyingIslandState` — so when the question is answered (here, by
/// voice, in NEO's page) or lapses, the island is exactly what it was.
///
/// **The buttons own every click on the surface**: a click on one answers;
/// a click beside them gives the surface the keyboard and does nothing
/// else — it never opens NEO's chat or the dashboard by accident. **Keys**:
/// Return allows, Esc cancels — while the island has the keyboard (after a
/// click on the surface, or when one of NotchHub's panels already had it).
/// The surface does NOT take the keyboard by itself as it appears, and no
/// key is captured globally: a Return meant for the app you are typing in
/// must never become an Allow. Allow — clicked or keyed — counts only after
/// the buttons have been up 0.6 s; Cancel always.
///
/// The answer is the command NEO's own page sends from its card
/// (`{"cmd":"confirm","yes":…,"action_id":…}`), over the listener's host
/// connection. No sound: NotchHub has none anywhere, and this does not
/// invent one. Ghost Mode hides the buttons with the rest of the island.
extension NotchHubApp {

    /// Whether the buttons are on the island now: a card is waiting and
    /// NEO's chat panel (whose page shows the card itself) is not open.
    var neoConfirmShowing: Bool {
        neoConfirm.card != nil && panel != .neo && featureSettings.isEnabled(.neo)
    }

    /// The model heard a fact that changed what shows: bring the island in
    /// line — the buttons pop out, or the island springs back to what it was.
    func neoConfirmChanged(wasShowing: Bool) {
        renderIsland()
        if neoConfirmShowing { neoConfirmAnnounce() }
        if neoConfirm.card == nil { neoConfirmAnnounced = nil }
        if !neoConfirmShowing { neoConfirmReleaseKeyboard() }
        log("neo: confirm \(neoConfirmShowing ? "showing \(neoConfirm.card?.tool ?? "")" : "gone")")
    }

    /// Keeps the model's view of the chat panel current (the buttons come
    /// up when the panel closes with a card still waiting, and their guard
    /// starts then). Called as the island renders.
    func syncNeoConfirm(at now: Date = Date()) {
        guard neoConfirm.chat(open: panel == .neo, at: now) else { return }
        if neoConfirm.isShowing { neoConfirmAnnounce() }
        if !neoConfirm.isShowing { neoConfirmReleaseKeyboard() }
    }

    /// Tells assistive technology the buttons are up, and for what — once
    /// per card.
    func neoConfirmAnnounce() {
        guard let card = neoConfirm.card, neoConfirmAnnounced != card.actionID else { return }
        neoConfirmAnnounced = card.actionID
        NSAccessibility.post(
            element: window as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: card.announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    /// The surface: the two buttons, the hovered one lifted.
    func neoConfirmContent(_ card: NeoConfirmCard) -> AnyView {
        var hovered: NeoConfirmChoice?
        if case let .neoConfirm(choice)? = hoveredControl { hovered = choice }
        return AnyView(NeoConfirmView(card: card, hovered: hovered) { [weak self] choice in
            self?.neoConfirmChoose(choice, by: "accessibility")
        })
    }

    // MARK: - Clicks and keys

    /// A click while the buttons show: on one, the answer; anywhere else on
    /// the surface, the keyboard (so Return and Esc work) and nothing more.
    /// Either way the click is the surface's — it never reaches the island
    /// underneath. Returns whether the buttons were showing.
    func neoConfirmControlHit(at point: NSPoint) -> Bool {
        guard currentIslandState() == .neoConfirm else { return false }
        let frame = window.localFrame(for: .neoConfirm, content: islandModel.contentSize)
        if let choice = NeoConfirmLayout.choice(at: point, in: frame, notchInset: window.notchHeight) {
            neoConfirmChoose(choice, by: "click")
        } else {
            neoConfirmTakeKeyboard()
        }
        return true
    }

    /// A key while the island's window is key. Return / Enter allow, Esc
    /// cancels; both are the surface's while it shows (a guarded or repeated
    /// Return is swallowed, never passed to a panel underneath).
    func neoConfirmKey(_ code: UInt16, isRepeat: Bool) -> Bool {
        // Only keys the island was given (a click on it, or a panel of
        // NotchHub's that had the keyboard): never ones it still holds from
        // Search Screen's card, which took them without the user's click — a
        // Return meant for the user's app must never become an Allow.
        guard window.needsInteraction else { return false }
        guard currentIslandState() == .neoConfirm, NeoConfirmKey.handles(keyCode: code) else { return false }
        if let choice = NeoConfirmKey.choice(forKeyCode: code, isRepeat: isRepeat) {
            neoConfirmChoose(choice, by: "key")
        }
        return true
    }

    /// The user chose. Allow before its guard does nothing (the buttons had
    /// only just appeared); otherwise the answer goes to NEO's core and the
    /// island springs back at once.
    func neoConfirmChoose(_ choice: NeoConfirmChoice, by how: String) {
        let now = Date()
        _ = neoConfirm.chat(open: panel == .neo, at: now)
        guard let answer = neoConfirm.answer(choice, at: now) else {
            log("neo: confirm \(choice.rawValue) by \(how) ignored (guard, or nothing showing)")
            return
        }
        monitor?.neoConfirm(answer)
        log("neo: confirm \(choice.rawValue) by \(how)")
        neoConfirmChanged(wasShowing: true)
        // The pet drops its "!" with the buttons, not when the core's state catches up.
        refreshNeoPet()
    }

    /// Gives the surface the keyboard at the user's own click on it.
    func neoConfirmTakeKeyboard() {
        guard !window.needsInteraction else { return }
        neoConfirmTookKeyboard = true
        window.needsInteraction = true
    }

    /// Hands the keyboard back when the buttons go, unless a panel that
    /// needs it has opened meanwhile.
    func neoConfirmReleaseKeyboard() {
        guard neoConfirmTookKeyboard else { return }
        neoConfirmTookKeyboard = false
        if panel == .none { window.needsInteraction = false }
    }
}
