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
