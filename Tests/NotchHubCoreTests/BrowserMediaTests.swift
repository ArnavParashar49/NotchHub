import Foundation
import Testing
@testable import NotchHubCore

@Suite("Browser media")
struct BrowserMediaTests {

    @Test("YouTube's unread badge is not a new track")
    func unreadBadgeStripped() {
        // The flicker: YouTube rewrites its tab title whenever the unread count
        // changes, so the same song arrived as "Song", "(1) Song", "(2) Song"…
        // and each one read as a different track. They must all normalise to
        // the same string, or the island tears itself down and springs open
        // again every time a notification lands.
        let same = [
            "Rick Astley - Never Gonna Give You Up - YouTube",
            "(1) Rick Astley - Never Gonna Give You Up - YouTube",
            "(12) Rick Astley - Never Gonna Give You Up - YouTube",
            "  (3)   Rick Astley - Never Gonna Give You Up - YouTube  ",
            "▶ Rick Astley - Never Gonna Give You Up - YouTube",
        ].map(BrowserMedia.normalizeTitle)
        #expect(Set(same).count == 1, "\(Set(same))")
        #expect(same[0] == "Rick Astley - Never Gonna Give You Up")
    }

    @Test("only the trailing site suffix is removed, never one inside the title")
    func suffixHandling() {
        #expect(BrowserMedia.normalizeTitle("Lo-fi beats - SoundCloud") == "Lo-fi beats")
        #expect(BrowserMedia.normalizeTitle("Song - Spotify") == "Song")
        // A title that MENTIONS the site keeps it — the old code replaced every
        // occurrence anywhere in the string.
        #expect(BrowserMedia.normalizeTitle("How - YouTube - changed music - YouTube")
                == "How - YouTube - changed music")
        // Nothing to strip.
        #expect(BrowserMedia.normalizeTitle("Just a title") == "Just a title")
        #expect(BrowserMedia.normalizeTitle("") == "")
    }

    @Test("a closed tab clears the island far sooner than an unanswerable query")
    func stopThresholds() {
        // The reported bug: closing a YouTube tab left the island playing for
        // the better part of half a minute, because a tab that had genuinely
        // gone was counted as a transient failure.
        #expect(BrowserMedia.stopAfterEmptyPolls < BrowserMedia.stopAfterFailedPolls)
        // Fast enough to feel immediate at the 2 s poll interval…
        #expect(BrowserMedia.stopAfterEmptyPolls <= 2)
        // …but never so eager that one mid-navigation poll drops a live track.
        #expect(BrowserMedia.stopAfterEmptyPolls >= 2)
    }

    @Test("'no media tab' and 'could not ask' are different answers")
    func probeIsThreeWay() {
        #expect(BrowserMedia.Probe.none != BrowserMedia.Probe.failed)
        #expect(BrowserMedia.Probe.playing(title: "a", url: "b") != .none)
        #expect(BrowserMedia.Probe.playing(title: "a", url: "b") != .failed)
    }
}
