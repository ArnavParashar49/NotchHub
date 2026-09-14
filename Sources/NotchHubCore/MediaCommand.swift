import Foundation

/// A transport action the island can ask the system's media player to perform.
///
/// The island never talks to Music or Spotify directly: it asks the system's
/// media framework to carry out the command, which routes it to whichever
/// player currently owns the now-playing session. That is why the same three
/// buttons drive any player.
public enum MediaCommand: String, CaseIterable, Sendable {
    case previous
    case togglePlayPause
    case next

    /// The system media framework's own command codes. These are the stable
    /// numeric values of its `MRMediaRemoteCommand` enum; keeping them here —
    /// named, in one place — means the private API's shape is declared once
    /// rather than spelled inline at the call site.
    public var rawCommandCode: Int32 {
        switch self {
        case .previous: return 5
        case .togglePlayPause: return 2
        case .next: return 4
        }
    }
}

/// The transport state a media surface renders.
///
/// The buttons are derived from this rather than held as view state, so a
/// player that pauses itself (the end of a track, the phone taking over) is
/// reflected the moment the next now-playing event arrives.
public struct MediaTransport: Equatable {
    public var isPlaying: Bool
    public var canControl: Bool

    public init(isPlaying: Bool = true, canControl: Bool = true) {
        self.isPlaying = isPlaying
        self.canControl = canControl
    }

    /// The symbol for the centre button: a play triangle while paused, a pair
    /// of pause bars while playing.
    public var playPauseSymbol: String {
        isPlaying ? "pause.fill" : "play.fill"
    }
}
