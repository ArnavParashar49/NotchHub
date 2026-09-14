import Foundation
import Testing
@testable import NotchHubCore

@Suite("Activity lifetimes")
struct ActivityLifetimeTests {

    @Test("upsert updates the matching activity in place and keeps its id")
    func upsertKeepsIdentity() {
        let queue = ActivityQueue()
        let first = queue.upsert(.download(name: "a.zip", progress: 0.1))
        let second = queue.upsert(.download(name: "a.zip", progress: 0.6))
        #expect(queue.all.count == 1)
        #expect(second.id == first.id)
        #expect(queue.current?.progress == 0.6)
    }

    @Test("upsert keeps concurrent downloads separate")
    func upsertSeparatesByTitle() {
        let queue = ActivityQueue()
        queue.upsert(.download(name: "a.zip", progress: 0.1))
        queue.upsert(.download(name: "b.zip", progress: 0.2))
        #expect(queue.all.count == 2)
    }

    @Test("removing a focused transient's kind hands the island back")
    func removeKindClearsTransient() {
        let queue = ActivityQueue()
        let music = queue.push(.music(title: "Solo", artist: "Frank Ocean"))
        queue.focusTemporarily(.volume(0.4))
        queue.remove(kind: .volume)
        #expect(queue.current?.id == music.id)
    }

    @Test("finished surfaces are transient, never stuck on the island")
    func finishedSurfacesExpire() {
        let later = Date().addingTimeInterval(60)
        #expect(Activity.downloadFinished(name: "a.zip").isExpired(at: later))
        #expect(Activity.codingAgentFinished("Claude Code").isExpired(at: later))
    }

    @Test("a download with no known total shows bytes, not an invented percentage")
    func indeterminateDownload() {
        let activity = Activity.download(name: "a.zip", bytesSoFar: 5_000_000)
        #expect(activity.progress == nil)
        #expect(activity.compactText == "5 MB")
    }

    @Test("withAutoDismiss changes only the lifetime")
    func withAutoDismissKeepsEverythingElse() {
        let music = Activity.music(title: "Solo", artist: "Frank Ocean", source: "com.spotify.client")
        let short = music.withAutoDismiss(8)
        #expect(short.id == music.id)
        #expect(short.autoDismiss == 8)
        #expect(short.sourceBundleID == "com.spotify.client")
        #expect(short.title == music.title)
    }

    @Test("MediaRemote's playback rate decides whether a track is playing")
    func playbackRate() {
        #expect(NowPlayingInfo.from(["kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 0.0)]).isPlaying == false)
        #expect(NowPlayingInfo.from(["kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1.0)]).isPlaying)
        #expect(NowPlayingInfo.from([:]).isPlaying)
    }
}

@Suite("Clipboard privacy")
struct ClipboardPrivacyTests {

    @Test("password-manager marker types are never recorded")
    func concealedTypesIgnored() {
        #expect(ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundleID: nil))
        #expect(ClipboardPrivacy.shouldIgnore(types: ["org.nspasteboard.TransientType"], sourceBundleID: nil))
    }

    @Test("copies from a password manager are ignored even without a marker")
    func passwordManagerSourceIgnored() {
        #expect(ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"], sourceBundleID: "com.1password.1password"))
    }

    @Test("ordinary copies are recorded")
    func ordinaryCopyKept() {
        #expect(!ClipboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.TextEdit"))
    }
}
