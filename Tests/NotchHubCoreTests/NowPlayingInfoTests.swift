import Foundation
import Testing
@testable import NotchHubCore

@Suite("NowPlayingInfo")
struct NowPlayingInfoTests {

    @Test("reads title, artist and artwork from the framework's dictionary")
    func parsesFullDictionary() {
        let artwork = Data([0x89, 0x50, 0x4E, 0x47])
        let raw: [String: Any] = [
            NowPlayingInfo.Key.title: "Midnight City",
            NowPlayingInfo.Key.artist: "M83",
            NowPlayingInfo.Key.artworkData: artwork,
        ]
        let info = NowPlayingInfo.from(raw)
        #expect(info.title == "Midnight City")
        #expect(info.artist == "M83")
        #expect(info.artwork == artwork)
    }

    @Test("a player with no artwork yields nil, so the island falls back to its glyph")
    func noArtwork() {
        let raw: [String: Any] = [
            NowPlayingInfo.Key.title: "Some Radio Stream",
            NowPlayingInfo.Key.artist: "Unknown",
        ]
        let info = NowPlayingInfo.from(raw)
        #expect(info.title == "Some Radio Stream")
        #expect(info.artwork == nil)
    }

    @Test("empty artwork data is treated as absent, not as a broken image")
    func emptyArtworkIsAbsent() {
        let raw: [String: Any] = [
            NowPlayingInfo.Key.title: "Track",
            NowPlayingInfo.Key.artworkData: Data(),
        ]
        #expect(NowPlayingInfo.from(raw).artwork == nil)
    }

    @Test("an empty dictionary yields an empty snapshot rather than a crash")
    func emptyDictionary() {
        let info = NowPlayingInfo.from([:])
        #expect(info.title == nil)
        #expect(info.artist == nil)
        #expect(info.artwork == nil)
    }

    @Test("whitespace-only fields are normalised to nil")
    func whitespaceNormalised() {
        let raw: [String: Any] = [
            NowPlayingInfo.Key.title: "   ",
            NowPlayingInfo.Key.artist: "\n",
        ]
        let info = NowPlayingInfo.from(raw)
        #expect(info.title == nil)
        #expect(info.artist == nil)
    }

    @Test("a value of the wrong type is ignored, not fatal")
    func wrongTypesIgnored() {
        // A player is free to send an NSNumber where a String is expected.
        let raw: [String: Any] = [
            NowPlayingInfo.Key.title: 42,
            NowPlayingInfo.Key.artworkData: "not data",
        ]
        let info = NowPlayingInfo.from(raw)
        #expect(info.title == nil)
        #expect(info.artwork == nil)
    }

    @Test("sameTrack ignores artwork, so a re-post is not a track change")
    func sameTrackIgnoresArtwork() {
        let a = NowPlayingInfo(title: "Solo", artist: "Frank Ocean", artwork: Data([1]))
        let b = NowPlayingInfo(title: "Solo", artist: "Frank Ocean", artwork: Data([2]))
        let c = NowPlayingInfo(title: "Solo", artist: "Frank Ocean", artwork: nil)
        #expect(a.sameTrack(as: b))
        #expect(a.sameTrack(as: c))
    }

    @Test("a different title or artist is a different track")
    func differentTrack() {
        let a = NowPlayingInfo(title: "Solo", artist: "Frank Ocean")
        #expect(!a.sameTrack(as: NowPlayingInfo(title: "Nikes", artist: "Frank Ocean")))
        #expect(!a.sameTrack(as: NowPlayingInfo(title: "Solo", artist: "Someone Else")))
    }
}
