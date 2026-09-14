import Foundation

/// The one diagnostic log every layer writes through.
///
/// Silent unless the app was launched with `--verbose`, so a normal launch
/// never floods Console with per-poll chatter (privacy polls, now-playing
/// notifications, listener start-up) — those lines exist to verify behaviour,
/// not to run in production.
public enum NotchLog {
    public static let isVerbose = CommandLine.arguments.contains("--verbose")

    public static func debug(_ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        FileHandle.standardError.write(Data("[notchhub] \(message())\n".utf8))
    }
}
