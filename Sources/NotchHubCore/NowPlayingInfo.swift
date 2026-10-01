import Foundation

/// One snapshot of what the system is playing, normalised away from the
/// private API that produced it.
///
/// The now-playing plumbing has two halves: a thin, untestable call into the
/// system's media framework, and this — a pure value that parses whatever
/// dictionary that call hands back. Keeping the parsing here means the
/// interesting logic (which keys carry the artwork, what happens when a player
/// supplies none) is covered by ordinary unit tests.
public struct NowPlayingInfo: Equatable {
    public var title: String?
    public var artist: String?
    /// The artwork bytes the player published, if any. Players that ship no
    /// art (a local file with no tags, a radio stream) leave this nil and the
    /// island falls back to its glyph.
    public var artwork: Data?
    /// The player's playback rate: `0` paused, `1` playing. `nil` when the
    /// player did not report one.
    public var playbackRate: Double?

    public init(title: String? = nil, artist: String? = nil, artwork: Data? = nil, playbackRate: Double? = nil) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.playbackRate = playbackRate
    }

    /// Whether the snapshot describes something actually playing. A player
    /// that reports no rate is assumed to be playing — it published a track,
    /// and there is no signal to say otherwise.
    public var isPlaying: Bool { (playbackRate ?? 1) > 0 }

    /// The keys the system's media framework uses in its now-playing
    /// dictionary. They are plain string constants — the framework exports
    /// them as `CFString` symbols whose value is their own name.
    enum Key {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let artworkIdentifier = "kMRMediaRemoteNowPlayingInfoArtworkIdentifier"
        static let artworkWidth = "kMRMediaRemoteNowPlayingInfoArtworkDataWidth"
        static let artworkHeight = "kMRMediaRemoteNowPlayingInfoArtworkDataHeight"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    }

    /// Parses the media framework's dictionary.
    ///
    /// Values arrive as `Any` from a `CFDictionary`, so each is unwrapped
    /// defensively: a player is free to send an `NSNumber` where a `String` is
    /// expected, and a missing key must read as "unknown", never as a crash.
    public static func from(_ raw: [String: Any]) -> NowPlayingInfo {
        var info = NowPlayingInfo()
        info.title = (raw[Key.title] as? String)?.trimmed
        info.artist = (raw[Key.artist] as? String)?.trimmed

        // Artwork may arrive as Data or as a bridged NSData.
        if let data = raw[Key.artworkData] as? Data, !data.isEmpty {
            info.artwork = data
        }

        // The rate arrives as a bridged NSNumber.
        if let rate = raw[Key.playbackRate] as? NSNumber {
            info.playbackRate = rate.doubleValue
        }

        if info.title?.isEmpty == true { info.title = nil }
        if info.artist?.isEmpty == true { info.artist = nil }
        return info
    }

    /// Whether two snapshots describe the same piece of music. Artwork is
    /// deliberately ignored: it is large, and a player that re-sends the same
    /// track with identical bytes should not be treated as a change.
    public func sameTrack(as other: NowPlayingInfo) -> Bool {
        title == other.title && artist == other.artist
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Browser tabs

/// Turns a browser tab's title into a track, and decides when a track has
/// really stopped.
///
/// This is the "last resort" source: a media tab open in a browser. It is the
/// one the island gets wrong most easily, because a tab title is not a track —
/// it is a string the page rewrites whenever it likes.
public enum BrowserMedia {

    /// The site suffixes a tab title carries.
    static let siteSuffixes = [" - YouTube", " - Spotify", " - SoundCloud", " - Apple Music"]

    /// Strips the decoration a page puts around its title, leaving the part
    /// that actually names what is playing.
    ///
    /// YouTube prefixes the tab title with its unread count — "(3) Some Song -
    /// YouTube" — and rewrites it whenever that count changes. Taken at face
    /// value each rewrite reads as a DIFFERENT track, so the island tore the
    /// surface down and sprang a new one open every time a notification
    /// arrived, which is what the flicker was.
    public static func normalizeTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // "(3) ", "(12) " — an unread badge, not part of the name.
        while let range = title.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) {
            title.removeSubrange(range)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A leading "▶" some players add while playing.
        if let first = title.first, first == "▶" || first == "\u{25B6}" {
            title = String(title.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for suffix in siteSuffixes where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return title
    }

    /// What a poll of the browsers found.
    ///
    /// "No media tab" and "the query failed" are deliberately NOT the same
    /// answer. A tab that is gone is a fact the island should act on at once;
    /// a script that could not run (the browser busy, Automation not yet
    /// granted) says nothing at all and must not clear a playing track. Folding
    /// the two together is why a closed tab took ten polls to disappear.
    public enum Probe: Equatable, Sendable {
        /// A media tab is open, with this title and URL.
        case playing(title: String, url: String)
        /// The browsers answered, and none of them has a media tab.
        case none
        /// No browser could be asked.
        case failed
    }

    /// How many consecutive "no media tab" answers end a track.
    ///
    /// Two, not one: a browser mid-navigation can answer "none" for a single
    /// poll between one video and the next, and dropping the island on that
    /// would flicker. Two answers at the poll interval is fast enough to feel
    /// immediate and slow enough to ride out a page load.
    public static let stopAfterEmptyPolls = 2

    /// How many consecutive FAILED queries end a track. Much more forgiving:
    /// a failure is an absence of information, not evidence of silence.
    public static let stopAfterFailedPolls = 10
}
