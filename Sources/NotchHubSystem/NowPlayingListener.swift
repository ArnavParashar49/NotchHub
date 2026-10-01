import AppKit
import Foundation
import NotchHubCore

/// The browsers the now-playing fallback can read, and the AppleScript that
/// finds (or focuses) a media tab in them.
///
/// Scripts fetch every tab's URL in ONE Apple event per property
/// (`URL of every tab of every window`) instead of asking tab by tab — a
/// per-tab loop costs an inter-process round trip for every open tab, every
/// poll.
public enum MediaBrowsers {

    public struct Browser: Equatable, Sendable {
        public let bundleID: String
        public let appName: String
        /// The tab property holding its title (`title` in Chromium, `name` in Safari).
        let titleProperty: String
        /// The window property naming the frontmost tab.
        let activeTabProperty: String
        /// Whether this is Safari's scripting dictionary rather than Chromium's.
        let isSafari: Bool
    }

    public static let all: [Browser] = [
        Browser(bundleID: "com.google.Chrome", appName: "Google Chrome", titleProperty: "title", activeTabProperty: "active tab", isSafari: false),
        Browser(bundleID: "com.brave.Browser", appName: "Brave Browser", titleProperty: "title", activeTabProperty: "active tab", isSafari: false),
        Browser(bundleID: "com.microsoft.edgemac", appName: "Microsoft Edge", titleProperty: "title", activeTabProperty: "active tab", isSafari: false),
        Browser(bundleID: "com.apple.Safari", appName: "Safari", titleProperty: "name", activeTabProperty: "current tab", isSafari: true),
    ]

    public static func browser(bundleID: String) -> Browser? {
        all.first { $0.bundleID == bundleID }
    }

    /// URL fragments that mark a tab as a media player.
    static let mediaURLMarkers = ["youtube.com/watch", "music.youtube.com", "soundcloud.com", "open.spotify.com"]

    private static func isMedia(_ variable: String) -> String {
        "(" + mediaURLMarkers.map { "\(variable) contains \"\($0)\"" }.joined(separator: " or ") + ")"
    }

    /// Returns `title|||url` for the first media tab (the front tab wins), or
    /// the literal "none".
    ///
    /// "none" rather than an empty string on purpose: an empty result is what
    /// AppleScript also gives back when the script could not run at all, and
    /// the island has to tell "there is no media tab" (act now) apart from "I
    /// could not ask" (say nothing). See `BrowserMedia.Probe`.
    static func findMediaTabScript(_ browser: Browser) -> String {
        """
        tell application "\(browser.appName)"
            if (count of windows) is 0 then return "none"
            try
                set curURL to URL of \(browser.activeTabProperty) of front window
                if \(isMedia("curURL")) then return (\(browser.titleProperty) of \(browser.activeTabProperty) of front window) & "|||" & curURL
            end try
            set urlLists to URL of every tab of every window
            set titleLists to \(browser.titleProperty) of every tab of every window
            repeat with i from 1 to count of urlLists
                set urls to item i of urlLists
                repeat with j from 1 to count of urls
                    set u to item j of urls
                    if \(isMedia("u")) then return (item j of item i of titleLists) & "|||" & u
                end repeat
            end repeat
            return "none"
        end tell
        """
    }

    /// Brings the browser forward with its first media tab selected.
    public static func activateMediaTabScript(_ browser: Browser) -> String {
        let select = browser.isSafari
            ? "set current tab of w to tab j of w"
            : "set active tab index of w to j"
        return """
        tell application "\(browser.appName)"
            activate
            set urlLists to URL of every tab of every window
            repeat with i from 1 to count of urlLists
                set urls to item i of urlLists
                repeat with j from 1 to count of urls
                    set u to item j of urls
                    if \(isMedia("u")) then
                        set w to window i
                        \(select)
                        set index of w to 1
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        """
    }
}

/// Observes now-playing state.
///
/// Apple exposes no public now-playing API, so this combines: the distributed
/// notifications Music and Spotify broadcast; Spotify's AppleScript (for the
/// artwork URL); the private MediaRemote framework; and, as a last resort, the
/// media tabs open in a browser. Honest boundary: if a player does not
/// announce itself, the island simply shows nothing for it — and on recent
/// macOS releases MediaRemote may return nothing to a third-party app at all.
public final class NowPlayingListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var observers: [NSObjectProtocol] = []
    private var lastTitle: String?
    private var lastArtist: String?
    private var lastPlaying: Bool?
    private var lastArtworkData: Data?

    /// Artwork for recent tracks, keyed by "title\u{0}artist". Players announce
    /// the same track many times; the artwork never changes within a track, so
    /// it is fetched once and reused.
    private var artworkCache: [String: Data] = [:]
    private var artworkOrder: [String] = []
    private let maxArtworkCache = 12

    private var pollTimer: Timer?

    /// Serial, because `NSAppleScript` is not thread-safe: the poll timer and a
    /// change notification must never run scripts at the same time.
    private let queryQueue = DispatchQueue(label: "notchhub.nowplaying.query", qos: .utility)
    /// When the in-flight poll began (main queue). A slow AppleScript must not
    /// let polls pile up behind it; a poll that never reports back is given up
    /// on after `pollTimeout`.
    private var pollStartedAt: Date?
    private let pollTimeout: TimeInterval = 10

    /// Consecutive polls where the browsers answered "no media tab". This is
    /// evidence, so it clears a track quickly.
    private var consecutiveEmpty = 0
    /// The confirming poll a first "no media tab" answer schedules.
    private var confirmStopWork: DispatchWorkItem?
    /// How soon that confirmation runs. Short, because it exists to make the
    /// stop feel immediate: waiting out another full poll interval to confirm
    /// what the browser has already said is most of the delay the user sees.
    private static let stopConfirmDelay: TimeInterval = 0.4
    /// Consecutive polls where no browser could be asked at all. This is the
    /// absence of evidence, so it clears a track only very reluctantly.
    private var consecutiveFailures = 0

    /// The distributed notifications players post, and who posts them.
    private static let playerNotifications: [(name: String, bundleID: String)] = [
        ("com.apple.Music.playerInfo", "com.apple.Music"),
        ("com.apple.iTunes.playerInfo", "com.apple.Music"),
        ("com.spotify.client.PlaybackStateChanged", "com.spotify.client"),
    ]

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()

        for player in Self.playerNotifications {
            let token = center.addObserver(
                forName: NSNotification.Name(player.name),
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.handle(note, source: player.bundleID)
            }
            observers.append(token)
        }

        // Register as a now-playing observer so the system actively pushes
        // changes to us, then observe its change notification.
        MediaRemote.registerForNowPlayingNotifications()
        let systemToken = center.addObserver(
            forName: NSNotification.Name(MediaRemote.nowPlayingDidChangeNotification),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.poll()
        }
        observers.append(systemToken)

        // Poll as a fallback for players that post nothing. The timer MUST be
        // in the `.common` run-loop mode or it stalls during event tracking.
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func stop() {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        pollStartedAt = nil
        artworkCache.removeAll()
        artworkOrder.removeAll()
        // A restarted listener must not inherit a half-counted stop.
        cancelStopConfirmation()
        consecutiveEmpty = 0
        consecutiveFailures = 0
    }

    // MARK: - Polling

    private func poll() {
        if let started = pollStartedAt, Date().timeIntervalSince(started) < pollTimeout {
            return // the previous poll is still running
        }
        pollStartedAt = Date()
        // The AppleScript queries block while the target app responds, so
        // they must NEVER run on the main thread.
        queryQueue.async { [weak self] in
            self?.queryNowPlayingOffMain()
        }
    }

    /// Main queue: the in-flight poll has reported back.
    private func pollFinished() {
        pollStartedAt = nil
    }

    /// Runs on `queryQueue`.
    private func queryNowPlayingOffMain() {
        let apps = NSWorkspace.shared.runningApplications
        let spotifyRunning = apps.contains(where: { $0.bundleIdentifier == "com.spotify.client" })

        // 1. Spotify's own scripting (the only source of its artwork URL).
        if spotifyRunning, let spotifyResult = querySpotify(), !spotifyResult.isEmpty {
            let parts = spotifyResult.components(separatedBy: "|||")
            if parts.count >= 3 {
                let title = parts[0]
                let artist = parts[1]
                let isPlaying = parts[2] == "playing"
                let artworkUrlStr = parts.count >= 4 ? parts[3] : ""
                DispatchQueue.main.async { [weak self] in
                    self?.pollFinished()
                    self?.handleSpotifyResult(
                        title: title,
                        artist: artist,
                        isPlaying: isPlaying,
                        artworkUrlString: artworkUrlStr.isEmpty ? nil : artworkUrlStr
                    )
                }
                return
            }
        }

        // 2. The system's MediaRemote aggregator.
        MediaRemote.fetch { [weak self] snapshot in
            guard let self else { return }

            if let title = snapshot.title, !title.isEmpty {
                self.pollFinished()
                self.update(
                    title: title,
                    artist: snapshot.artist ?? "",
                    isPlaying: snapshot.isPlaying,
                    artwork: snapshot.artwork,
                    source: nil
                )
                return
            }

            // 3. Media tabs in a browser.
            self.queryQueue.async { [weak self] in
                self?.queryBrowserFallbackOffMain()
            }
        }
    }

    /// Handles a Spotify result on the main queue: reuse cached artwork or
    /// fetch it from URL / MediaRemote, then announce the track.
    private func handleSpotifyResult(title: String, artist: String, isPlaying: Bool, artworkUrlString: String?) {
        let source = "com.spotify.client"
        let key = "\(title)\u{0}\(artist)"
        if let cached = artworkCache[key] {
            update(title: title, artist: artist, isPlaying: isPlaying, artwork: cached, source: source)
            return
        }

        // Announce immediately; the artwork follows.
        update(title: title, artist: artist, isPlaying: isPlaying, artwork: nil, source: source)

        if let urlStr = artworkUrlString, let url = URL(string: urlStr) {
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self else { return }
                guard let data, error == nil, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    NotchLog.debug("spotify: artwork fetch failed error=\(error?.localizedDescription ?? "none") status=\((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return
                }
                DispatchQueue.main.async {
                    self.cacheArtwork(data, for: key)
                    self.update(title: title, artist: artist, isPlaying: isPlaying, artwork: data, source: source)
                }
            }.resume()
            return
        }

        MediaRemote.fetch { [weak self] snapshot in
            guard let self, let data = snapshot.artwork else { return }
            self.cacheArtwork(data, for: key)
            self.update(title: title, artist: artist, isPlaying: isPlaying, artwork: data, source: source)
        }
    }

    /// Runs on `queryQueue`: asks each running browser for a media tab.
    ///
    /// A browser that answers "none" has ANSWERED — that is not a failure, and
    /// the loop keeps asking the others before concluding anything.
    private func queryBrowserFallbackOffMain() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var anyAnswered = false

        for browser in MediaBrowsers.all where running.contains(browser.bundleID) {
            // Nil here means the script could not run; "none" means it ran and
            // found nothing.
            guard let result = runScript(MediaBrowsers.findMediaTabScript(browser)) else { continue }
            anyAnswered = true
            guard result != "none" else { continue }

            let parts = result.components(separatedBy: "|||")
            let parsed = parseBrowserMedia(rawTitle: parts[0], urlString: parts.count > 1 ? parts[1] : "")
            DispatchQueue.main.async { [weak self] in
                self?.pollFinished()
                self?.handleBrowserResult(parsed, source: browser.bundleID)
            }
            return
        }

        let probe: BrowserMedia.Probe = anyAnswered ? .none : .failed
        DispatchQueue.main.async { [weak self] in
            self?.pollFinished()
            self?.browserFallbackEmpty(probe)
        }
    }

    /// Main queue: the browsers produced no track. `probe` says whether that is
    /// because there is none, or because none of them could be asked.
    ///
    /// The distinction is the whole point. Closing a YouTube tab used to leave
    /// the island playing it for the better part of half a minute, because a
    /// tab that had genuinely gone was counted as ten transient failures.
    private func browserFallbackEmpty(_ probe: BrowserMedia.Probe) {
        // Music and Spotify announce stops themselves; a quiet browser poll
        // must not clear their track.
        let apps = NSWorkspace.shared.runningApplications
        let playerRunning = apps.contains {
            $0.bundleIdentifier == "com.apple.Music" || $0.bundleIdentifier == "com.spotify.client"
        }
        if playerRunning {
            cancelStopConfirmation()
            consecutiveEmpty = 0
            consecutiveFailures = 0
            return
        }

        let threshold: Int
        if probe == .none {
            consecutiveEmpty += 1
            consecutiveFailures = 0
            threshold = BrowserMedia.stopAfterEmptyPolls
        } else {
            consecutiveFailures += 1
            threshold = BrowserMedia.stopAfterFailedPolls
        }
        let count = probe == .none ? consecutiveEmpty : consecutiveFailures

        // Not yet sure, but the browser has already said there is nothing: ask
        // again straight away rather than waiting out another whole poll
        // interval. The confirmation is what the user experiences as the delay.
        if probe == .none, count < threshold, lastTitle != nil {
            scheduleStopConfirmation()
            return
        }
        guard count >= threshold, lastTitle != nil else { return }

        cancelStopConfirmation()
        NotchLog.debug("nowPlaying: stopped after \(count) \(probe == .none ? "empty" : "failed") poll(s)")
        emit(SystemEvent(source: .nowPlaying, payload: .nowPlayingStopped))
        lastTitle = nil
        lastArtist = nil
        lastPlaying = nil
        lastArtworkData = nil
        consecutiveEmpty = 0
        consecutiveFailures = 0
    }

    /// Re-polls shortly, to confirm (or contradict) a first "no media tab".
    private func scheduleStopConfirmation() {
        cancelStopConfirmation()
        let work = DispatchWorkItem { [weak self] in
            self?.confirmStopWork = nil
            self?.poll()
        }
        confirmStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopConfirmDelay, execute: work)
    }

    private func cancelStopConfirmation() {
        confirmStopWork?.cancel()
        confirmStopWork = nil
    }

    /// Handles a parsed browser result on the main queue: reuse cached artwork,
    /// fetch a YouTube thumbnail, then announce the track.
    private func handleBrowserResult(_ parsed: (title: String, artist: String, videoId: String?), source: String) {
        cancelStopConfirmation()
        consecutiveEmpty = 0
        consecutiveFailures = 0
        let key = "\(parsed.title)\u{0}\(parsed.artist)"
        if let cached = artworkCache[key] {
            update(title: parsed.title, artist: parsed.artist, isPlaying: true, artwork: cached, source: source)
            return
        }

        if let videoId = parsed.videoId {
            fetchYouTubeThumbnail(videoId: videoId) { [weak self] data in
                guard let self else { return }
                if let data { self.cacheArtwork(data, for: key) }
                self.update(title: parsed.title, artist: parsed.artist, isPlaying: true, artwork: data, source: source)
            }
        } else {
            update(title: parsed.title, artist: parsed.artist, isPlaying: true, artwork: nil, source: source)
        }
    }

    // MARK: - Scripts

    private func querySpotify() -> String? {
        runScript("""
        if application "Spotify" is running then
            tell application "Spotify"
                try
                    set t to name of current track
                    set a to artist of current track
                    set s to player state
                    set ps to "paused"
                    if s is playing then set ps to "playing"
                    set art to ""
                    try
                        set art to artwork url of current track
                    end try
                    return t & "|||" & a & "|||" & ps & "|||" & art
                on error
                    return ""
                end try
            end tell
        else
            return ""
        end if
        """)
    }

    /// Runs a script on `queryQueue`, returning its non-empty string result.
    private func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        guard error == nil, let value = output.stringValue, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Parsing

    private func parseBrowserMedia(rawTitle: String, urlString: String) -> (title: String, artist: String, videoId: String?) {
        let clean = BrowserMedia.normalizeTitle(rawTitle)

        var artist = "YouTube"
        var title = clean
        if urlString.contains("spotify.com") {
            artist = "Spotify"
        } else if urlString.contains("soundcloud.com") {
            artist = "SoundCloud"
        }

        let parts = clean.components(separatedBy: " - ")
        if parts.count >= 2 {
            artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            title = parts[1...].joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (title: title, artist: artist, videoId: extractYouTubeVideoId(from: urlString))
    }

    private func extractYouTubeVideoId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItem = components.queryItems?.first(where: { $0.name == "v" }) {
            return queryItem.value
        }
        let pathComponents = url.pathComponents
        if url.host?.contains("youtu.be") == true, pathComponents.count > 1 {
            return pathComponents[1]
        }
        if let shortsIndex = pathComponents.firstIndex(of: "shorts"), shortsIndex + 1 < pathComponents.count {
            return pathComponents[shortsIndex + 1]
        }
        return nil
    }

    // MARK: - Artwork

    private func fetchYouTubeThumbnail(videoId: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            let ok = data != nil && error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok ? data : nil) }
        }.resume()
    }

    private func fetchSpotifyArtwork(trackID: String, completion: @escaping (Data?) -> Void) {
        // Spotify's oEmbed endpoint returns a thumbnail URL for a track id.
        var components = URLComponents(string: "https://open.spotify.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: trackID)]
        guard let url = components?.url else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumbUrlStr = json["thumbnail_url"] as? String,
                  let thumbUrl = URL(string: thumbUrlStr) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            URLSession.shared.dataTask(with: thumbUrl) { data, _, _ in
                DispatchQueue.main.async { completion(data) }
            }.resume()
        }.resume()
    }

    private func cacheArtwork(_ data: Data, for key: String) {
        if artworkCache[key] == nil {
            artworkOrder.append(key)
        }
        artworkCache[key] = data
        while artworkOrder.count > maxArtworkCache {
            artworkCache.removeValue(forKey: artworkOrder.removeFirst())
        }
    }

    // MARK: - Emit

    /// Main queue.
    private func update(title: String, artist: String, isPlaying: Bool, artwork: Data?, source: String?) {
        let key = "\(title)\u{0}\(artist)"
        if let artwork {
            cacheArtwork(artwork, for: key)
        }

        // Only emit on a real change — but an artwork-only update (same track,
        // art now available) must still re-emit so the island can show the art.
        let sameTrack = title == lastTitle && artist == lastArtist && isPlaying == lastPlaying
        let cachedArt = artworkCache[key]
        let hasNewArtwork = (artwork != nil || cachedArt != nil) && lastArtworkData == nil
        guard !sameTrack || hasNewArtwork else { return }

        if !sameTrack { lastArtworkData = nil }
        lastTitle = title
        lastArtist = artist
        lastPlaying = isPlaying
        lastArtworkData = artwork ?? cachedArt

        if title.isEmpty && !isPlaying {
            emit(SystemEvent(source: .nowPlaying, payload: .nowPlayingStopped))
            return
        }

        emitNowPlaying(title: title, artist: artist, isPlaying: isPlaying, artwork: artwork ?? cachedArt, source: source)
    }

    /// Main queue: a player's distributed notification.
    private func handle(_ note: Notification, source: String) {
        guard let info = note.userInfo else { return }
        NotchLog.debug("notification: \(note.name.rawValue) keys=\(info.keys.map { String(describing: $0) })")

        let state = (info["Player State"] as? String) ?? (info["State"] as? String)
        let title = (info["Name"] as? String) ?? (info["Title"] as? String)
        let artist = info["Artist"] as? String
        let trackID = info["Track ID"] as? String

        let isPlaying: Bool
        switch state?.lowercased() {
        case "paused", "stopped": isPlaying = false
        default: isPlaying = true
        }

        guard let title, !title.isEmpty else {
            if state?.lowercased() == "stopped" {
                lastTitle = nil
                lastArtist = nil
                lastPlaying = nil
                lastArtworkData = nil
                emit(SystemEvent(source: .nowPlaying, payload: .nowPlayingStopped))
            }
            return
        }

        let resolvedArtist = artist ?? ""
        let key = "\(title)\u{0}\(resolvedArtist)"
        update(title: title, artist: resolvedArtist, isPlaying: isPlaying, artwork: artworkCache[key], source: source)
        guard artworkCache[key] == nil else { return }

        // Spotify: the oEmbed API returns artwork for a track id, no permission needed.
        if let trackID, trackID.contains("spotify:track:") {
            fetchSpotifyArtwork(trackID: trackID) { [weak self] data in
                guard let self, let data else { return }
                self.cacheArtwork(data, for: key)
                self.update(title: title, artist: resolvedArtist, isPlaying: isPlaying, artwork: data, source: source)
            }
            return
        }

        MediaRemote.fetch { [weak self] snapshot in
            guard let self, let data = snapshot.artwork else { return }
            self.cacheArtwork(data, for: key)
            self.update(title: title, artist: resolvedArtist, isPlaying: isPlaying, artwork: data, source: source)
        }
    }

    private func emitNowPlaying(title: String, artist: String, isPlaying: Bool, artwork: Data?, source: String?) {
        emit(SystemEvent(
            source: .nowPlaying,
            payload: .nowPlaying(title: title, artist: artist, isPlaying: isPlaying, artwork: artwork, source: source)
        ))
    }
}
