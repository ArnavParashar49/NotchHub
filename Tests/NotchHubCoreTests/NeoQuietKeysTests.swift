import Foundation
import Testing
@testable import NotchHubCore

@Suite("Keys Search Screen's card takes quietly, and when they go back")
struct NeoQuietKeysTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("a fold gives them back as it starts — once")
    func goBackWhenHome() {
        #expect(NeoQuietKeys.returnDelay == 0, "the keys go back as the fold starts: no key typed after Esc is lost")
        var keys = NeoQuietKeys()
        #expect(keys.phase == .none && !keys.isTaken)
        keys.take()
        #expect(keys.isTaken)
        let due = keys.fold(isKey: true, at: t0)
        #expect(due == t0.addingTimeInterval(NeoQuietKeys.returnDelay))
        #expect(keys.isReturning && !keys.isTaken, "the page has let go: canBecomeKey, ⌘-keys are no longer the card's")
        let again = keys.fold(isKey: true, at: t0)
        #expect(again == nil, "a second fold changes nothing")
        let back = keys.due(due!)
        #expect(back)
        #expect(keys.phase == .none && keys.returnAt == nil)
        let twice = keys.due(due!)
        #expect(!twice, "once")
    }

    @Test("a timer left over from an earlier fold never gives back the keys of a later one")
    func staleTimer() {
        var keys = NeoQuietKeys()
        keys.take()
        let first = keys.fold(isKey: true, at: t0)!
        // A new card opens 100 ms later (its panel takes the keys again), and folds at once.
        keys.take()
        let whileTaken = keys.due(first)
        #expect(!whileTaken, "taken again: the old timer does nothing")
        let second = keys.fold(isKey: true, at: t0.addingTimeInterval(0.1))!
        let stale = keys.due(first)
        #expect(!stale, "the first fold's timer, mid-way through the second fold")
        #expect(keys.isReturning)
        let own = keys.due(second)
        #expect(own)
    }

    @Test("a key pressed while they go back: given back at once")
    func typed() {
        var keys = NeoQuietKeys()
        let none = keys.typed()
        #expect(!none, "no keys of the card's: the key is the window's as ever")
        keys.take()
        let taken = keys.typed()
        #expect(!taken, "the card has them: the key is the page's")
        let due = keys.fold(isKey: true, at: t0)!
        let typed = keys.typed()
        #expect(typed)
        #expect(keys.phase == .none)
        let again = keys.typed()
        #expect(!again)
        let timer = keys.due(due)
        #expect(!timer, "the timer finds them gone already")
    }

    @Test("a click elsewhere took them: the card folds (away) — and nothing is given back after a fold")
    func resigned() {
        var keys = NeoQuietKeys()
        keys.take()
        let away = keys.resigned()
        #expect(away, "taken: the panel folds, the core hears \"away\"")
        let after = keys.fold(isKey: false, at: t0)
        #expect(after == nil, "the fold that follows has nothing to give back")
        keys.take()
        let notKey = keys.fold(isKey: false, at: t0)
        #expect(notKey == nil, "no longer key when the fold starts: nothing to give back")
        #expect(keys.phase == .none)
        keys.take()
        let due = keys.fold(isKey: true, at: t0)!
        let duringReturn = keys.resigned()
        #expect(!duringReturn, "going back already: the fold is not told twice")
        let timer = keys.due(due)
        #expect(!timer)
    }

    @Test("a panel that takes the keys for real keeps them: nothing is given back behind its back")
    func interaction() {
        var keys = NeoQuietKeys()
        keys.take()
        let due = keys.fold(isKey: true, at: t0)!
        keys.interaction()
        #expect(keys.phase == .none)
        let timer = keys.due(due)
        let typed = keys.typed()
        #expect(!timer && !typed)
        keys.take()
        keys.interaction()
        #expect(keys.isTaken, "the card's own panel asking for the keys changes nothing here")
    }
}
