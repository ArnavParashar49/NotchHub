import CoreGraphics
import Foundation

/// The teleprompter: a script that scrolls itself past the notch while you read.
///
/// The scroll position is NOT accumulated frame by frame. It is derived from
/// the clock — `anchor + speed × (now − resumedAt)` — so the motion is exactly
/// constant however often the view happens to redraw, a dropped frame cannot
/// make the text drift, and pausing is just a matter of folding the elapsed
/// distance back into the anchor. That is what keeps it from stuttering, and it
/// is why pause/resume lands on the very same word.
public struct TeleprompterState: Equatable, Sendable {

    /// What the user is doing with it right now.
    public enum Mode: Equatable, Sendable {
        /// Writing, pasting or loading a script.
        case compose
        /// Reading it.
        case running
    }

    public var mode: Mode
    public var script: String
    /// Distance already scrolled when the prompter was last paused, in points.
    public private(set) var anchor: Double
    /// When the current run began. `nil` while paused.
    public private(set) var resumedAt: Date?
    /// Points per second, at 1×.
    public static let baseSpeed: Double = 14
    /// The speed multipliers the ± controls step through. Reading pace is
    /// personal, so the range is wide, and the steps are fine near 1× where
    /// people actually settle.
    public static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]
    /// Index into `speeds`.
    public private(set) var speedIndex: Int
    /// How far the script CAN scroll, in points: the rendered height of the
    /// text, less the reading window, plus the tail that lets the last line
    /// come to rest in the middle of the window rather than at its top edge.
    /// The view measures it. Until it has, the prompter never reaches its end.
    public var scrollDistance: Double

    public init(
        mode: Mode = .compose,
        script: String = "",
        anchor: Double = 0,
        resumedAt: Date? = nil,
        speedIndex: Int = 2,
        scrollDistance: Double = 0
    ) {
        self.mode = mode
        self.script = script
        self.anchor = max(0, anchor)
        self.resumedAt = resumedAt
        self.speedIndex = min(max(0, speedIndex), Self.speeds.count - 1)
        self.scrollDistance = max(0, scrollDistance)
    }

    // MARK: - Speed

    public var speedMultiplier: Double { Self.speeds[speedIndex] }

    /// Points per second at the current setting.
    public var pointsPerSecond: Double { Self.baseSpeed * speedMultiplier }

    /// "1×", "1.25×" — no trailing zeros, always with the multiplication sign.
    public var speedLabel: String {
        String(format: "%g×", speedMultiplier)
    }

    public var canGoFaster: Bool { speedIndex < Self.speeds.count - 1 }
    public var canGoSlower: Bool { speedIndex > 0 }

    /// Changes speed without moving the text.
    ///
    /// The distance covered so far is folded into the anchor FIRST, so the new
    /// rate applies from here on rather than being retroactively applied to the
    /// whole run — which would make the script jump when the user nudged it.
    public mutating func setSpeedIndex(_ index: Int, now: Date = Date()) {
        let clamped = min(max(0, index), Self.speeds.count - 1)
        guard clamped != speedIndex else { return }
        if resumedAt != nil {
            anchor = offset(at: now)
            resumedAt = now
        }
        speedIndex = clamped
    }

    public mutating func faster(now: Date = Date()) { setSpeedIndex(speedIndex + 1, now: now) }
    public mutating func slower(now: Date = Date()) { setSpeedIndex(speedIndex - 1, now: now) }

    // MARK: - Transport

    public var isRunning: Bool { resumedAt != nil }

    /// Whether there is anything to read.
    public var hasScript: Bool {
        !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How far the script has scrolled at `now`, in points.
    ///
    /// Clamped to `maxOffset`, so the prompter parks at the end of the script
    /// instead of scrolling it off into nothing.
    public func offset(at now: Date = Date()) -> Double {
        guard let resumedAt else { return min(anchor, maxOffset) }
        let elapsed = max(0, now.timeIntervalSince(resumedAt))
        return min(anchor + pointsPerSecond * elapsed, maxOffset)
    }

    /// The furthest the script may scroll.
    public var maxOffset: Double { max(0, scrollDistance) }

    /// Whether the script has scrolled all the way through.
    public func isFinished(at now: Date = Date()) -> Bool {
        scrollDistance > 0 && offset(at: now) >= maxOffset
    }

    /// Starts or resumes scrolling. Restarts from the top when the script has
    /// already run to the end — the natural thing to want from a finished take.
    public mutating func play(now: Date = Date()) {
        guard hasScript else { return }
        if isFinished(at: now) { anchor = 0 }
        mode = .running
        resumedAt = now
    }

    /// Stops where it is. The position is kept exactly, so resuming picks up on
    /// the same word.
    public mutating func pause(now: Date = Date()) {
        guard let _ = resumedAt else { return }
        anchor = offset(at: now)
        resumedAt = nil
    }

    public mutating func togglePlaying(now: Date = Date()) {
        if isRunning { pause(now: now) } else { play(now: now) }
    }

    /// Back to the first line, without changing whether it is running — a
    /// second take starts the moment you ask for it.
    public mutating func restart(now: Date = Date()) {
        anchor = 0
        if resumedAt != nil { resumedAt = now }
    }

    /// Back to composing, paused at the top.
    public mutating func edit() {
        pause()
        anchor = 0
        mode = .compose
    }

    /// Replaces the script and rewinds. Loading a new script mid-take and
    /// keeping the old scroll position would land in the middle of nowhere.
    public mutating func load(_ text: String) {
        script = text
        anchor = 0
        resumedAt = nil
        scrollDistance = 0
    }

    /// How far through the script the reader is, 0…1, for the progress hairline.
    public func progress(at now: Date = Date()) -> Double {
        guard maxOffset > 0 else { return 0 }
        return min(1, max(0, offset(at: now) / maxOffset))
    }
}

// MARK: - Layout

/// Something the teleprompter does when clicked.
public enum TeleprompterAction: Equatable, Sendable {
    case playPause
    case restart
    case slower
    case faster
    /// Back to the script, to change it.
    case edit
    case close
}

/// The geometry of the teleprompter's clickable areas.
///
/// While READING, the prompter's controls are drawn and hit-tested by the
/// window rather than being real buttons: a teleprompter that took key focus
/// would pull it out of the app the user is presenting from, which is the one
/// thing it must never do. While COMPOSING there is a real text editor, so that
/// mode does take focus — and has no drawn controls at all.
public enum TeleprompterLayout {
    public static let horizontalInset: CGFloat = 20
    /// The control bar's height, along the bottom of the panel.
    public static let barHeight: CGFloat = 30
    public static let barBottomInset: CGFloat = 12
    public static let buttonSize = CGSize(width: 30, height: 26)
    public static let buttonSpacing: CGFloat = 4
    /// The speed readout between the − and + buttons.
    public static let speedWidth: CGFloat = 46
    /// The reading window's inset from the panel's top (below the notch strip)
    /// and bottom (above the control bar).
    public static let readingTopInset: CGFloat = 10
    public static let readingBottomGap: CGFloat = 8

    /// The order the transport controls appear in, left to right.
    public static let transport: [TeleprompterAction] = [.playPause, .restart]
    /// The trailing cluster: edit the script, then close.
    public static let trailing: [TeleprompterAction] = [.edit, .close]

    /// The reading window — where the script is drawn and clipped.
    public static func readingFrame(in frame: CGRect, notchInset: CGFloat) -> CGRect {
        let top = frame.maxY - notchInset - readingTopInset
        let bottom = frame.minY + barBottomInset + barHeight + readingBottomGap
        return CGRect(
            x: frame.minX + horizontalInset,
            y: bottom,
            width: frame.width - horizontalInset * 2,
            height: max(0, top - bottom)
        )
    }

    /// Every clickable area for a running prompter, in AppKit coordinates.
    public static func actions(in frame: CGRect) -> [(action: TeleprompterAction, rect: CGRect)] {
        let y = frame.minY + barBottomInset + (barHeight - buttonSize.height) / 2
        var result: [(action: TeleprompterAction, rect: CGRect)] = []

        // Transport on the left.
        var x = frame.minX + horizontalInset
        for action in transport {
            result.append((action, CGRect(x: x, y: y, width: buttonSize.width, height: buttonSize.height)))
            x += buttonSize.width + buttonSpacing
        }

        // Edit and close on the right.
        var trailingX = frame.maxX - horizontalInset
        for action in trailing.reversed() {
            trailingX -= buttonSize.width
            result.append((action, CGRect(x: trailingX, y: y, width: buttonSize.width, height: buttonSize.height)))
            trailingX -= buttonSpacing
        }

        // Speed, centred: − readout +.
        let clusterWidth = buttonSize.width * 2 + speedWidth + buttonSpacing * 2
        var speedX = (frame.midX - clusterWidth / 2).rounded()
        result.append((.slower, CGRect(x: speedX, y: y, width: buttonSize.width, height: buttonSize.height)))
        speedX += buttonSize.width + buttonSpacing + speedWidth + buttonSpacing
        result.append((.faster, CGRect(x: speedX, y: y, width: buttonSize.width, height: buttonSize.height)))

        return result
    }

    /// The action under a point, or `nil` for a miss (a few points of slop).
    public static func action(at point: CGPoint, in frame: CGRect) -> TeleprompterAction? {
        actions(in: frame)
            .first { $0.rect.insetBy(dx: -2, dy: -4).contains(point) }?
            .action
    }

    /// Where the speed readout is drawn (between its two buttons).
    public static func speedRect(in frame: CGRect) -> CGRect {
        let y = frame.minY + barBottomInset + (barHeight - buttonSize.height) / 2
        let clusterWidth = buttonSize.width * 2 + speedWidth + buttonSpacing * 2
        let x = (frame.midX - clusterWidth / 2).rounded() + buttonSize.width + buttonSpacing
        return CGRect(x: x, y: y, width: speedWidth, height: buttonSize.height)
    }
}
