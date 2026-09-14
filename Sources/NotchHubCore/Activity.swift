import Foundation

/// Everything the island knows how to surface.
public enum ActivityKind: String, CaseIterable, Codable, Equatable {
    case music
    case volume
    case brightness
    case battery
    case lowBattery
    case timer
    case download
    case notification
    case airpods
    case bluetooth
    case recording
    case microphone
    case camera
    case calendar
    case focus
    case dnd
    case wifi
    case clipboard
    /// A live call the island can drive: timer, mute, camera, leave.
    case meeting
    /// On-device dictation, in progress.
    case dictation
    /// A coding agent (Claude Code, Codex, …) working on the machine.
    case codingAgent
    /// The frontmost app, dressed for the island.
    case skin
    case custom

    /// SF Symbol used when an activity of this kind does not supply its own.
    public var defaultSymbol: String {
        switch self {
        case .music: return "music.note"
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .battery: return "battery.100"
        case .lowBattery: return "battery.25"
        case .timer: return "timer"
        case .download: return "arrow.down.circle.fill"
        case .notification: return "bell.fill"
        case .airpods: return "airpodspro"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .recording: return "record.circle"
        case .microphone: return "mic.fill"
        case .camera: return "video.fill"
        case .calendar: return "calendar"
        case .focus: return "moon.fill"
        case .dnd: return "moon.zzz.fill"
        case .wifi: return "wifi"
        case .clipboard: return "doc.on.clipboard"
        case .meeting: return "video.fill"
        case .dictation: return "waveform"
        case .codingAgent: return "chevron.left.forwardslash.chevron.right"
        case .skin: return "app.fill"
        case .custom: return "sparkles"
        }
    }

    /// Baseline priority. Higher wins the island.
    public var basePriority: Int {
        switch self {
        case .lowBattery: return 90
        case .dictation: return 85
        case .recording, .microphone, .camera: return 80
        case .meeting: return 75
        case .timer: return 70
        case .codingAgent: return 65
        case .music: return 60
        case .download: return 55
        case .airpods, .bluetooth: return 50
        case .battery: return 45
        case .volume, .brightness: return 40
        case .calendar: return 35
        case .focus, .dnd, .wifi: return 30
        case .notification: return 25
        case .clipboard: return 20
        case .custom: return 15
        case .skin: return 10
        }
    }

    /// How long the island ling lingers when the activity does not specify.
    public var defaultAutoDismiss: TimeInterval {
        switch self {
        case .volume, .brightness: return 1.6
        case .battery, .wifi, .bluetooth, .airpods: return 2.4
        case .clipboard, .notification: return 3.0
        case .music, .timer, .download, .recording, .microphone, .camera,
             .lowBattery, .focus, .dnd, .calendar, .meeting, .dictation, .skin,
             .codingAgent, .custom:
            return 0 // persistent until replaced or explicitly removed
        }
    }
}

/// A single thing the island can show.
public struct Activity: Identifiable, Equatable {
    public let id: UUID
    public var kind: ActivityKind
    public var title: String
    public var subtitle: String?
    /// SF Symbol name; falls back to the kind's default.
    public var symbol: String?
    /// Higher wins. Defaults to the kind's baseline.
    public var priority: Int
    /// Seconds before auto-dismiss; `0` means persistent.
    public var autoDismiss: TimeInterval
    /// 0…1 progress for downloads / transfers.
    public var progress: Double?
    /// Elapsed seconds for timers / stopwatches.
    public var elapsed: TimeInterval?
    /// Raw image bytes for the media source's own artwork (album art), when the
    /// player exposes it. Rendered in place of the glyph; `nil` falls back to
    /// `symbol`.
    public var artwork: Data?
    /// Whether a media source is currently playing. Drives the transport's
    /// play/pause glyph. Meaningless for kinds that are not media.
    public var isPlaying: Bool
    /// The bundle identifier of the app the activity came from (the player
    /// behind a track), when known. Lets a click open the RIGHT app rather
    /// than guessing from whatever happens to be running.
    public var sourceBundleID: String?
    /// When the activity was created.
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ActivityKind,
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        priority: Int? = nil,
        autoDismiss: TimeInterval? = nil,
        progress: Double? = nil,
        elapsed: TimeInterval? = nil,
        artwork: Data? = nil,
        isPlaying: Bool = true,
        sourceBundleID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.priority = priority ?? kind.basePriority
        self.autoDismiss = autoDismiss ?? kind.defaultAutoDismiss
        self.progress = progress
        self.elapsed = elapsed
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.sourceBundleID = sourceBundleID
        self.createdAt = createdAt
    }

    /// This activity carrying a different identity — used to update an
    /// in-flight activity without changing the id the view is keyed on.
    public func withID(_ id: UUID) -> Activity {
        Activity(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            priority: priority,
            autoDismiss: autoDismiss,
            progress: progress,
            elapsed: elapsed,
            artwork: artwork,
            isPlaying: isPlaying,
            sourceBundleID: sourceBundleID,
            createdAt: createdAt
        )
    }

    /// This activity with a different lifetime (`0` = persistent).
    public func withAutoDismiss(_ seconds: TimeInterval) -> Activity {
        Activity(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            priority: priority,
            autoDismiss: seconds,
            progress: progress,
            elapsed: elapsed,
            artwork: artwork,
            isPlaying: isPlaying,
            sourceBundleID: sourceBundleID,
            createdAt: createdAt
        )
    }

    /// The symbol to render, resolved.
    public var resolvedSymbol: String { symbol ?? kind.defaultSymbol }

    /// The live value shown beside the title in the COMPACT bar.
    ///
    /// Compact renders `title` + this value (the subtitle for most kinds). The
    /// timer is the exception: its subtitle is deliberately empty in the
    /// expanded view (the trailing control renders the readout there), so
    /// without this the compact bar would show a bare "Timer" with no time.
    public var compactValue: String? {
        switch kind {
        case .timer:
            if let elapsed { return Activity.format(elapsed) }
            return subtitle
        default:
            return subtitle
        }
    }

    /// The single line the compact bar draws beside the glyph.
    ///
    /// A readout is named by its ICON — a speaker, a sun, a battery — so a
    /// redundant word would only eat width and clip on a narrow bar. Those
    /// kinds show just their live value (the percentage, the elapsed time).
    /// Kinds whose identity IS the text (a song, a sender, a network) keep
    /// their title.
    public var compactText: String? {
        switch kind {
        case .music:
            // Show the track title in the compact bar so the user can see
            // what is playing without hovering.
            return title
        case .volume, .brightness, .battery, .lowBattery, .download:
            // The percentage is the news; the glyph names the kind.
            if let progress { return "\(Int((progress * 100).rounded()))%" }
            return subtitle
        case .timer:
            return compactValue
        default:
            return title
        }
    }

    /// An optional second line for the compact bar (the artist under a song).
    public var compactDetail: String? {
        switch kind {
        case .music: return nil
        default: return nil
        }
    }

    /// Whether the island may grow beyond the compact pill to show this
    /// activity.
    ///
    /// A transient system readout — volume, brightness, battery, Wi-Fi, a
    /// device connecting — says everything it has in the compact bar: an icon
    /// and a live value. Expanding it would reveal nothing new, so the island
    /// stays a pill and a hover does not grow it. Only kinds with controls or a
    /// genuinely different detailed layout are worth expanding.
    public var canExpand: Bool {
        switch kind {
        case .music, .meeting, .dictation:
            return true
        case .volume, .brightness, .battery, .lowBattery, .wifi, .bluetooth,
             .airpods, .recording, .microphone, .camera, .calendar, .focus,
             .dnd, .clipboard, .notification, .codingAgent, .skin, .custom,
             .timer, .download:
            return false
        }
    }

    /// Whether HOVERING may grow the compact bar. A call's bar carries its own
    /// mute / leave buttons, so hover leaves it in place to be clicked; a click
    /// still opens the call panel (`canExpand`).
    public var expandsOnHover: Bool {
        switch kind {
        case .music, .dictation: return true
        default: return false
        }
    }

    /// Whether this activity should be dismissed at `now`.
    public func isExpired(at now: Date) -> Bool {
        guard autoDismiss > 0 else { return false }
        return now.timeIntervalSince(createdAt) >= autoDismiss
    }
}

// MARK: - Factories

public extension Activity {
    static func music(
        title: String,
        artist: String,
        isPlaying: Bool = true,
        artwork: Data? = nil,
        source: String? = nil
    ) -> Activity {
        Activity(
            kind: .music,
            title: title,
            subtitle: artist,
            symbol: isPlaying ? "music.note" : "play.fill",
            artwork: artwork,
            isPlaying: isPlaying,
            sourceBundleID: source
        )
    }

    static func volume(_ level: Double) -> Activity {
        let clamped = max(0, min(1, level))
        let symbol: String
        switch clamped {
        case 0: symbol = "speaker.slash.fill"
        case ..<0.34: symbol = "speaker.wave.1.fill"
        case ..<0.67: symbol = "speaker.wave.2.fill"
        default: symbol = "speaker.wave.3.fill"
        }
        return Activity(
            kind: .volume,
            title: "Volume",
            subtitle: "\(Int((clamped * 100).rounded()))%",
            symbol: symbol,
            progress: clamped
        )
    }

    static func brightness(_ level: Double) -> Activity {
        let clamped = max(0, min(1, level))
        return Activity(
            kind: .brightness,
            title: "Brightness",
            subtitle: "\(Int((clamped * 100).rounded()))%",
            symbol: "sun.max.fill",
            progress: clamped
        )
    }

    static func battery(percent: Int, charging: Bool) -> Activity {
        let clamped = max(0, min(100, percent))
        let symbol: String
        if charging {
            symbol = "battery.100.bolt"
        } else {
            switch clamped {
            case ..<13: symbol = "battery.0"
            case ..<38: symbol = "battery.25"
            case ..<63: symbol = "battery.50"
            case ..<88: symbol = "battery.75"
            default: symbol = "battery.100"
            }
        }
        return Activity(
            kind: charging ? .battery : .battery,
            title: charging ? "Charging" : "Battery",
            subtitle: "\(clamped)%",
            symbol: symbol,
            progress: Double(clamped) / 100
        )
    }

    static func lowBattery(percent: Int) -> Activity {
        Activity(
            kind: .lowBattery,
            title: "Low Battery",
            subtitle: "\(max(0, min(100, percent)))% remaining",
            symbol: "battery.25",
            progress: Double(max(0, min(100, percent))) / 100
        )
    }

    static func timer(elapsed: TimeInterval, label: String = "Timer") -> Activity {
        // No subtitle: the expanded view's trailing control renders the elapsed
        // readout in monospaced digits, and a subtitle carrying the same text
        // would show the time twice.
        Activity(
            kind: .timer,
            title: label,
            symbol: "timer",
            elapsed: elapsed
        )
    }

    /// A coding agent's run ended. Transient: an agent that finished is news
    /// for a moment, not a surface that should hold the island forever.
    static func codingAgentFinished(_ agent: String) -> Activity {
        Activity(
            kind: .codingAgent,
            title: agent,
            subtitle: "Finished",
            symbol: "checkmark.circle.fill",
            autoDismiss: 4
        )
    }

    static func download(name: String, progress: Double) -> Activity {
        let clamped = max(0, min(1, progress))
        return Activity(
            kind: .download,
            title: name,
            subtitle: "\(Int((clamped * 100).rounded()))%",
            symbol: "arrow.down.circle.fill",
            progress: clamped
        )
    }

    /// A download whose total size is unknown (Chrome's `.crdownload`, a
    /// `.part` file). Rather than invent a percentage, it reports the bytes
    /// received so far and carries no progress value.
    static func download(name: String, bytesSoFar: Int64) -> Activity {
        Activity(
            kind: .download,
            title: name,
            subtitle: TrayClip.byteLabel(Int(clamping: bytesSoFar)),
            symbol: "arrow.down.circle.fill"
        )
    }

    /// A download that landed. Transient, so the "Complete" readout clears.
    static func downloadFinished(name: String) -> Activity {
        Activity(
            kind: .download,
            title: name,
            subtitle: "Complete",
            symbol: "checkmark.circle.fill",
            autoDismiss: 3
        )
    }

    static func airpods(connected: Bool, name: String = "AirPods Pro") -> Activity {
        Activity(
            kind: .airpods,
            title: connected ? "Connected" : "Disconnected",
            subtitle: name,
            symbol: "airpodspro"
        )
    }

    static func notification(title: String, body: String) -> Activity {
        Activity(kind: .notification, title: title, subtitle: body, symbol: "bell.fill")
    }

    /// A live call the island can drive.
    static func meeting(_ meeting: Meeting) -> Activity {
        Activity(
            kind: .meeting,
            title: meeting.title.isEmpty ? meeting.app.name : meeting.title,
            subtitle: meeting.context,
            symbol: meeting.app.symbol
        )
    }

    /// On-device dictation in progress.
    static func dictation(_ session: DictationSession) -> Activity {
        Activity(
            kind: .dictation,
            title: "Dictation",
            subtitle: session.displayText,
            symbol: "waveform"
        )
    }

    /// The frontmost app, dressed for the island.
    static func skin(_ skin: AppSkin) -> Activity {
        Activity(
            kind: .skin,
            title: skin.name,
            subtitle: skin.state ?? skin.detail,
            symbol: skin.symbol
        )
    }

    /// `mm:ss` (or `h:mm:ss` past an hour).
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
