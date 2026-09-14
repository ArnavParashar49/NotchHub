import Foundation
import NotchHubCore

/// Reads the system's now-playing state, including artwork, from the private
/// `MediaRemote` framework.
///
/// Why the private framework: Apple ships no public now-playing API, and the
/// distributed notifications the media apps post carry the title and artist
/// but NOT the artwork. `MRMediaRemoteGetNowPlayingInfo` is the one call that
/// returns the artwork bytes, and it is the same call the system's own Control
/// Center UI uses — a radio stream, a local file and a streaming service all
/// surface through it.
///
/// Everything is loaded dynamically: if a future macOS drops or renames the
/// symbol the app simply reports no artwork and the island keeps its glyph,
/// rather than failing to launch.
public enum MediaRemote {

    private typealias GetNowPlayingInfoFn =
        @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    /// Resolved once; `nil` means this macOS does not offer the call.
    private static let getNowPlayingInfo: GetNowPlayingInfoFn? = {
        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        else { return nil }
        return unsafeBitCast(symbol, to: GetNowPlayingInfoFn.self)
    }()

    /// Whether the private call is available on this machine.
    public static var isAvailable: Bool { getNowPlayingInfo != nil }

    /// Registers the app as a now-playing observer so the system actively
    /// pushes now-playing changes to us instead of us having to poll.
    ///
    /// Without this, `MRMediaRemoteGetNowPlayingInfo` often returns an empty
    /// dictionary — the framework only tracks the session for registered
    /// clients. Registering is what makes YouTube-in-Chrome and Spotify show up.
    private typealias RegisterForNotificationsFn =
        @convention(c) (DispatchQueue) -> Void

    private static let registerForNotifications: RegisterForNotificationsFn? = {
        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        else { return nil }
        return unsafeBitCast(symbol, to: RegisterForNotificationsFn.self)
    }()

    /// The distributed notification the system posts when now-playing changes.
    /// Observing it gives us an event-driven path that fires the moment a track
    /// starts, stops, or changes — no polling delay.
    public static let nowPlayingDidChangeNotification =
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification"

    /// Registers for now-playing push notifications. Safe to call repeatedly;
    /// a no-op on macOS versions that do not offer the symbol.
    public static func registerForNowPlayingNotifications() {
        registerForNotifications?(DispatchQueue.main)
    }

    /// Fetches the current now-playing snapshot, off the main thread.
    ///
    /// The completion always runs, on the main queue, with whatever the system
    /// had — an empty snapshot if nothing is playing. Callers never wait.
    public static func fetch(completion: @escaping (NowPlayingInfo) -> Void) {
        guard let fn = getNowPlayingInfo else {
            DispatchQueue.main.async { completion(NowPlayingInfo()) }
            return
        }
        fn(DispatchQueue.global(qos: .utility)) { dictionary in
            let raw = (dictionary as? [String: Any]) ?? [:]
            let info = NowPlayingInfo.from(raw)
            DispatchQueue.main.async { completion(info) }
        }
    }
}

// MARK: - Transport

extension MediaRemote {

    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Void

    private static let sendCommand: SendCommandFn? = {
        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
        else { return nil }
        return unsafeBitCast(symbol, to: SendCommandFn.self)
    }()

    /// Whether this machine lets the island drive the player.
    public static var canControlTransport: Bool { sendCommand != nil }

    /// Asks the active player to perform a transport command.
    ///
    /// Returns whether the command could be dispatched at all — not whether the
    /// player honoured it. A media player is a separate process: it may ignore
    /// a pause during a crossfade, and there is no acknowledgement to wait for,
    /// so the island reports success only for the dispatch.
    @discardableResult
    public static func send(_ command: MediaCommand) -> Bool {
        guard let fn = sendCommand else { return false }
        fn(command.rawCommandCode, nil)
        return true
    }
}
