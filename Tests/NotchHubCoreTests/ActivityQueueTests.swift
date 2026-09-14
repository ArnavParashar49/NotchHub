import Foundation
import Testing
@testable import NotchHubCore

@Suite("ActivityQueue")
struct ActivityQueueTests {

    @Test("a fresh queue is empty")
    func startsEmpty() {
        let q = ActivityQueue()
        #expect(q.isEmpty)
        #expect(q.current == nil)
        #expect(q.stackCount == 0)
    }

    @Test("the highest-priority activity wins the island")
    func highestPriorityWins() {
        let q = ActivityQueue()
        q.push(.music(title: "Song", artist: "Artist"))
        q.push(.volume(0.5))
        q.push(.lowBattery(percent: 8))
        #expect(q.current?.kind == .lowBattery)
    }

    @Test("stack count reflects activities behind the primary")
    func stackCount() {
        let q = ActivityQueue()
        q.push(.music(title: "Song", artist: "Artist"))
        q.push(.volume(0.5))
        q.push(.timer(elapsed: 0))
        #expect(q.stackCount == 2)
    }

    @Test("removing by id promotes the next activity")
    func removeById() {
        let q = ActivityQueue()
        let timer = q.push(.timer(elapsed: 0))
        q.push(.music(title: "Song", artist: "Artist"))
        q.remove(id: timer.id)
        #expect(q.current?.kind == .music)
    }

    @Test("short-lived activities auto-dismiss")
    func autoDismiss() {
        let q = ActivityQueue()
        q.push(.volume(0.5)) // 1.6s lifetime
        #expect(q.current != nil)
        let dismissed = q.tick(now: Date().addingTimeInterval(5))
        #expect(dismissed.count == 1)
        #expect(q.current == nil)
        #expect(q.isEmpty)
    }

    @Test("persistent activities survive a tick")
    func persistentDoesNotAutoDismiss() {
        let q = ActivityQueue()
        q.push(.music(title: "Song", artist: "Artist"))
        #expect(q.tick(now: Date().addingTimeInterval(3600)).isEmpty)
        #expect(q.current != nil)
    }

    @Test("replaceable kinds supersede rather than stack")
    func replaceableKindSupersedes() {
        let q = ActivityQueue()
        q.push(.volume(0.3))
        q.push(.volume(0.7))
        #expect(q.all.count == 1)
        #expect(q.current?.progress == 0.7)
    }

    @Test("a new song replaces the old one, not stacks")
    func musicReplaces() {
        let q = ActivityQueue()
        q.push(.music(title: "A", artist: "1"))
        q.push(.music(title: "B", artist: "2"))
        // A new now-playing track supersedes the previous one — two songs
        // should never stack behind each other.
        #expect(q.all.count == 1)
        #expect(q.current?.title == "B")
    }

    @Test("removeAll clears the island")
    func removeAll() {
        let q = ActivityQueue()
        q.push(.music(title: "A", artist: "1"))
        q.push(.timer(elapsed: 0))
        q.removeAll()
        #expect(q.isEmpty)
    }

    // MARK: - Transient-return priority

    @Test("focusTemporarily surfaces a lower-priority activity over the persistent one")
    func focusTemporarilyWinsOverPersistent() {
        let q = ActivityQueue()
        q.push(.music(title: "Song", artist: "Artist")) // priority 60, persistent
        #expect(q.current?.kind == .music)

        let volume = Activity.volume(0.5) // priority 40, 1.6s lifetime
        q.focusTemporarily(volume)
        #expect(q.current?.id == volume.id)
        #expect(q.current?.kind == .volume)
    }

    @Test("after the transient's autoDismiss elapses, tick returns to the persistent activity")
    func transientReturnsToPersistent() {
        let q = ActivityQueue()
        let music = q.push(.music(title: "Song", artist: "Artist"))
        q.focusTemporarily(.volume(0.5))
        #expect(q.current?.kind == .volume)

        q.tick(now: Date().addingTimeInterval(5))
        #expect(q.current?.id == music.id)
        #expect(q.current?.kind == .music)
        #expect(q.all.contains { $0.kind == .volume } == false)
    }

    @Test("resumePersistent drops the transient immediately")
    func resumePersistentDropsTransient() {
        let q = ActivityQueue()
        let music = q.push(.music(title: "Song", artist: "Artist"))
        q.focusTemporarily(.volume(0.5))
        #expect(q.current?.kind == .volume)

        q.resumePersistent()
        #expect(q.current?.id == music.id)
    }

    @Test("a persistent transient is not auto-dismissed by tick")
    func persistentTransientSurvivesTick() {
        let q = ActivityQueue()
        q.focusTemporarily(.music(title: "Song", artist: "Artist")) // persistent
        #expect(q.current?.kind == .music)
        #expect(q.tick(now: Date().addingTimeInterval(3600)).isEmpty)
        #expect(q.current?.kind == .music)
    }

    @Test("timer ticks update one activity instead of stacking")
    func timerTicksDoNotStack() {
        let q = ActivityQueue()
        // Simulate ten seconds of 0.25s ticks — the real TimerService cadence.
        for tick in 0..<40 {
            q.push(.timer(elapsed: Double(tick) * 0.25))
        }
        #expect(q.stackCount == 0)
        #expect(q.current?.kind == .timer)
        // The newest tick wins, so the readout shows the latest time.
        #expect(q.current?.elapsed == 39 * 0.25)
    }
}
