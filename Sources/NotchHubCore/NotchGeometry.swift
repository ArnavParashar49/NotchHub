import AppKit
import CoreGraphics

/// Pure geometry for anchoring the island to the MacBook camera notch.
///
/// All math is expressed over plain `CGRect` values so it can be unit-tested
/// without a live display. `NotchGeometry.detect(on:)` is the only part that
/// touches `NSScreen`.
public struct NotchGeometry: Equatable {
    /// The full display frame this geometry was derived from. Panel surfaces
    /// (tray, meeting, teleprompter, camera, skin) are sized against it.
    public let screenFrame: CGRect
    /// The physical notch cutout, in screen coordinates.
    public let notchFrame: CGRect
    /// A pill just wider than the notch — the resting "compact" island.
    public let compactFrame: CGRect
    /// The fully expanded island.
    public let expandedFrame: CGRect
    /// The dashboard, revealed on click.
    public let interactiveFrame: CGRect
    /// Corner radius matching the notch's own curvature.
    public let cornerRadius: CGFloat
    /// Whether this display actually has a notch.
    public let hasNotch: Bool

    public init(
        notchFrame: CGRect,
        compactFrame: CGRect,
        expandedFrame: CGRect,
        interactiveFrame: CGRect,
        cornerRadius: CGFloat,
        hasNotch: Bool,
        screenFrame: CGRect = .zero
    ) {
        self.notchFrame = notchFrame
        self.compactFrame = compactFrame
        self.expandedFrame = expandedFrame
        self.interactiveFrame = interactiveFrame
        self.cornerRadius = cornerRadius
        self.hasNotch = hasNotch
        self.screenFrame = screenFrame
    }

    // MARK: - Tuning

    /// How far the compact bar stretches to the LEFT of the notch edge.
    ///
    /// The compact bar is exactly notch-height and grows LEFT and RIGHT — it
    /// never expands downward, so a transient activity (a volume change, a
    /// battery readout) shows alongside the notch instead of as a pill hanging
    /// under it. The two sides are deliberately asymmetric: the left holds only
    /// the activity's glyph, so it stays snug — just the icon and a hair of
    /// inset — while the right holds the title and value and needs the room.
    public static let compactLeadOverhang: CGFloat = 40
    /// How far the compact bar stretches to the RIGHT of the notch edge —
    /// enough for a full track title beside its artist without truncating.
    public static let compactTrailOverhang: CGFloat = 116
    /// The resting width of a wing beside the notch, before its content has
    /// been measured.
    ///
    /// The wings are the sideways hover peek: a notch-height bar that grows
    /// LEFT and RIGHT of the cutout. Measured wings size each side to its own
    /// content (`IslandContentSize.wingLead`); this default is used for both.
    public static let wingWidth: CGFloat = 84
    /// How wide a wing actually gets once its content is measured — a browser's
    /// nav cluster, an agent's token readout — which is the widest the hover
    /// strip realistically becomes in use.
    ///
    /// `wingWidth` above is the strip's BARE resting width, before anything has
    /// been measured into it; the strip you actually see while hovering is
    /// almost always this instead. Surfaces that want to line up with the strip
    /// match this one, so they agree with it in practice rather than in theory.
    public static let wingContentWidth: CGFloat = 110
    /// A generous ceiling on how far the content-driven surfaces (the wings and
    /// the compact bar) may stretch from the notch edge.
    ///
    /// The island itself measures its real content and stays snug; this number
    /// only sizes the WINDOW envelope, so the window is wide enough to hold the
    /// island at its widest without ever needing to resize mid-animation.
    public static let maxContentOverhang: CGFloat = 300
    /// Expanded island width as a fraction of the screen width.
    public static let expandedWidthFraction: CGFloat = 0.34
    /// Hard ceiling on expanded width so it never sprawls on ultrawide displays.
    public static let expandedMaxWidth: CGFloat = 620
    /// Expanded island height.
    ///
    /// Proportioned to comfortably fit the notch (32pt) at the top plus the
    /// 52pt album artwork, track title/artist, transport cluster, and 4pt progress
    /// track below it with balanced vertical padding (10pt top, 10pt bottom).
    public static let expandedHeight: CGFloat = 88
    /// Height of the click dashboard (the `.interactive` state), notch strip
    /// included: a greeting and large clock, the next event, and a status bar.
    public static let interactiveHeight: CGFloat = 196
    /// Height of an app panel (browser, coding agent), notch strip included.
    public static let appPanelHeight: CGFloat = 216
    /// The tallest an app panel may grow (an agent with plan-limit rows).
    public static let appPanelMaxHeight: CGFloat = 300
    /// Fallback notch height when the display reports no safe-area inset.
    public static let fallbackNotchHeight: CGFloat = 32
    /// Fallback notch width when the display reports no safe-area inset.
    public static let fallbackNotchWidth: CGFloat = 200
    /// Dashboard width as a fraction of the screen width.
    public static let interactiveWidthFraction: CGFloat = 0.30
    /// Hard ceiling on the dashboard's width.
    public static let interactiveMaxWidth: CGFloat = 440

    // MARK: - Derivation

    /// Builds the geometry from a screen frame plus the notch's safe-area insets.
    ///
    /// - Parameters:
    ///   - screenFrame: The full display frame (`NSScreen.frame`).
    ///   - safeAreaInsets: The display's safe-area insets.
    ///   - auxiliaryLeft: The `auxiliaryTopLeftArea` rect, when the OS provides it.
    ///   - auxiliaryRight: The `auxiliaryTopRightArea` rect, when the OS provides it.
    public static func make(
        screenFrame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        auxiliaryLeft: CGRect? = nil,
        auxiliaryRight: CGRect? = nil
    ) -> NotchGeometry {
        let notchHeight = safeAreaInsets.top > 0 ? safeAreaInsets.top : fallbackNotchHeight

        // Preferred path: the OS hands us the two menu-bar regions flanking the
        // notch, so the notch is simply the gap between them.
        var notchWidth: CGFloat
        if let left = auxiliaryLeft, let right = auxiliaryRight {
            notchWidth = right.minX - left.maxX
        } else if safeAreaInsets.left > 0 || safeAreaInsets.right > 0 {
            notchWidth = screenFrame.width - safeAreaInsets.left - safeAreaInsets.right
        } else {
            // A notched display reports only a top inset; the notch width is not
            // derivable without the auxiliary areas, so fall back to a known-good
            // value rather than claiming the whole screen width.
            notchWidth = fallbackNotchWidth
        }

        if notchWidth <= 0 || notchWidth > screenFrame.width {
            notchWidth = fallbackNotchWidth
        }

        let hasNotch = safeAreaInsets.top > 0 || (auxiliaryLeft != nil && auxiliaryRight != nil)

        let notch = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        // The compact bar is asymmetric: a snug left wing for the glyph and a
        // wider right wing for the title. Its origin is set so the notch region
        // inside it still centres on the real notch — otherwise the cutout would
        // drift and content would land under the physical notch.
        let compactWidth = notchWidth + compactLeadOverhang + compactTrailOverhang
        let compact = CGRect(
            x: screenFrame.midX - compactLeadOverhang - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: compactWidth,
            height: notchHeight
        )

        let expandedWidth = min(screenFrame.width * expandedWidthFraction, expandedMaxWidth)
        let expanded = CGRect(
            x: screenFrame.midX - expandedWidth / 2,
            y: screenFrame.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )

        let interactiveWidth = min(screenFrame.width * interactiveWidthFraction, interactiveMaxWidth)
        let interactive = CGRect(
            x: screenFrame.midX - interactiveWidth / 2,
            y: screenFrame.maxY - interactiveHeight,
            width: interactiveWidth,
            height: interactiveHeight
        )

        // Sharp corners, deliberately. The island is meant to read as a
        // rectangular continuation of the notch cutout — same hard edges, same
        // black — not as a rounded pill floating below it. Any radius here
        // shows up as a visible curve against the notch's straight sides.
        let radius: CGFloat = 0

        return NotchGeometry(
            notchFrame: notch,
            compactFrame: compact,
            expandedFrame: expanded,
            interactiveFrame: interactive,
            cornerRadius: radius,
            hasNotch: hasNotch,
            screenFrame: screenFrame
        )
    }

    /// Detects the notch on a live screen.
    public static func detect(on screen: NSScreen) -> NotchGeometry {
        let auxiliaryLeft = screen.auxiliaryTopLeftArea
        let auxiliaryRight = screen.auxiliaryTopRightArea
        return make(
            screenFrame: screen.frame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryLeft: auxiliaryLeft,
            auxiliaryRight: auxiliaryRight
        )
    }

    /// Detects the notch on the main display, falling back to a synthetic
    /// geometry when no screen is available (headless / self-test runs).
    public static func detectMain() -> NotchGeometry {
        if let screen = NSScreen.main {
            return detect(on: screen)
        }
        return make(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0)
        )
    }

    /// The frame the island should occupy for a given presentation state.
    public func frame(for state: IslandState) -> CGRect {
        frame(for: state, content: .default)
    }

    /// The frame the island should occupy, sized to the actual content.
    ///
    /// The wings and the compact bar are CONTENT-DRIVEN: their width grows to
    /// fit however many icons and how much text are showing, and collapses back
    /// when there is less. The expanded and panel states keep their fixed
    /// display-sized frames.
    public func frame(for state: IslandState, content: IslandContentSize) -> CGRect {
        switch state {
        case .idle:
            // The pet's dock beside the notch (see `PetDock`); without one — or
            // while the pet hides in the notch — idle is exactly the notch.
            guard let dock = content.petDock, dock.reach > 0 else { return notchFrame }
            // For the first moment NEO listens the word "Listening" stands
            // between the notch and the pet, so the dock reaches that much
            // further out — on the pet's side only. (Afterwards the slot is
            // 0: the glow behind the pet takes no room.)
            let slot = max(0, content.listeningSlot)
            return compactBar(
                lead: dock.lead + (dock.side == .left ? slot : 0),
                trail: dock.trail + (dock.side == .right ? slot : 0)
            )
        case .wings: return compactBar(lead: content.wingLead ?? content.wingSide, trail: content.wingSide)
        case .compact: return compactBar(lead: content.compactLead, trail: content.compactTrail)
        case .expanded: return expandedFrame
        case .interactive: return interactiveFrame
        case .appPanel: return appPanelFrame(height: content.panelHeight)
        case .tray: return trayFrame
        case .meeting: return meetingFrame
        case .skin: return petPanelFrame
        case .settings: return settingsFrame
        case .fileDrop: return fileDropFrame
        case .teleprompter: return teleprompterFrame
        case .teleprompterCompose: return teleprompterComposeFrame
        case .camera: return cameraFrame(expanded: false)
        case .cameraExpanded: return cameraFrame(expanded: true)
        case .neoPanel: return neoPanelFrame(page: content.neoPanel)
        }
    }

    /// NEO's panel: its chat page under the notch strip, centred on the
    /// notch like every other panel, sized to what the page asked for within
    /// `NeoPanelLayout`'s limits for this screen.
    public func neoPanelFrame(page: CGSize?) -> CGRect {
        let size = NeoPanelLayout.pageSize(requested: page, screen: CGSize(width: screenWidth, height: screenHeight))
        return panel(width: size.width, height: (notchFrame.height + size.height).rounded())
    }

    /// The sideways hover peek: a bar exactly as tall as the notch that
    /// stretches left and right of it.
    ///
    /// This is the shape the island takes when the cursor arrives at a resting
    /// notch — it grows *sideways*, hugging the screen's top edge, so it never
    /// covers the content below the notch. The left wing carries the frontmost
    /// app's identity; the right wing carries live status.
    public var wingsFrame: CGRect {
        wingsBar(sideWidth: Self.wingWidth)
    }

    /// Equal wings of a specific per-side width, centred on the notch. The
    /// island itself uses `compactBar(lead:trail:)` so each side fits its
    /// content.
    ///
    /// The width is clamped to `maxContentOverhang`: beyond that the island
    /// would outgrow the window envelope, and a clip at the screen edge is
    /// worse than a little truncation in the content.
    public func wingsBar(sideWidth: CGFloat) -> CGRect {
        let side = min(max(0, sideWidth), Self.maxContentOverhang)
        let width = notchFrame.width + side * 2
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - notchFrame.height,
            width: width,
            height: notchFrame.height
        )
    }

    /// The compact bar sized to a specific lead/trail width.
    ///
    /// The compact bar is asymmetric — a snug left wing for the glyph and a
    /// wider right wing for the title — so its origin is set from the LEAD
    /// width, keeping the notch region inside it centred on the real notch.
    /// Without that, the cutout drifts and content lands under the physical
    /// notch.
    public func compactBar(lead: CGFloat, trail: CGFloat) -> CGRect {
        let l = min(max(0, lead), Self.maxContentOverhang)
        let t = min(max(0, trail), Self.maxContentOverhang)
        let width = notchFrame.width + l + t
        return CGRect(
            x: screenFrame.midX - l - notchFrame.width / 2,
            y: screenFrame.maxY - notchFrame.height,
            width: width,
            height: notchFrame.height
        )
    }

    // MARK: - Panel frames
    //
    // These hang from the notch, centred, and are sized against the display.
    // They never exceed the screen, so a small display still gets a sane panel.

    /// The screen's usable width, falling back to the derived notch geometry
    /// when a caller built this struct without a screen frame (tests).
    private var screenWidth: CGFloat {
        screenFrame.width > 0 ? screenFrame.width : compactFrame.width + 1200
    }

    /// The screen's height, with the same fallback.
    private var screenHeight: CGFloat {
        screenFrame.height > 0 ? screenFrame.height : notchFrame.maxY
    }

    /// A panel of `width` × `height`, centred on the NOTCH and hung from the top
    /// of the screen so it grows out of it.
    ///
    /// Centred on `notchFrame.midX` and hung from `notchFrame.maxY` rather than
    /// on the screen's own width and height: a display whose frame does not
    /// start at the origin (a MacBook driven beside an external primary, where
    /// `NSScreen.main.frame.origin` is the external display's width) would
    /// otherwise put every panel hundreds of points away from the notch the
    /// island is anchored to — on the wrong display entirely.
    private func panel(width: CGFloat, height: CGFloat) -> CGRect {
        let w = min(width, screenWidth)
        return CGRect(
            x: notchFrame.midX - w / 2,
            y: notchFrame.maxY - height,
            width: w,
            height: height
        )
    }

    /// The clipboard Tray: a compact browser for a text-only history.
    ///
    /// Half the height it used to be. It was sized as a wide, tall sheet back
    /// when clips could be images and screenshots and needed room to be
    /// recognised; a list of copied STRINGS does not, and at the old size most
    /// of it was empty black.
    ///
    /// Its width is the HOVER STRIP's, so the two surfaces share an outline:
    /// the Tray opens as the bar you were already looking at, growing straight
    /// down out of it rather than to some unrelated width of its own.
    ///
    /// Matched to the strip carrying CONTENT (`wingContentWidth`) rather than to
    /// its bare resting width: the strip is content-driven, so the one on screen
    /// when you reach for the Tray is the wider one nearly every time.
    public var trayFrame: CGRect {
        panel(width: wingsBar(sideWidth: Self.wingContentWidth).width, height: 210)
    }

    /// A live call's control panel.
    public var meetingFrame: CGRect {
        panel(width: min(screenWidth * 0.36, 560), height: 132)
    }

    /// The frontmost app's own panel: as wide as the dashboard, a little taller.
    public var appPanelFrame: CGRect { appPanelFrame(height: nil) }

    /// An app panel of a content-driven height, clamped to the standard and
    /// maximum heights.
    public func appPanelFrame(height: CGFloat?) -> CGRect {
        let h = min(max(height ?? Self.appPanelHeight, Self.appPanelHeight), Self.appPanelMaxHeight)
        return panel(width: min(screenWidth * Self.interactiveWidthFraction, Self.interactiveMaxWidth), height: h)
    }

    /// The frontmost-app skin: a compact identity strip.
    public var skinFrame: CGRect {
        panel(width: max(360, PetPanelLayout.panelWidth), height: 96)
    }

    /// The pet's panel: the same centred surface every other panel uses.
    ///
    /// It used to hang from whichever island edge the pet was clicked beside,
    /// which made a click on the pet at the right of a compact bar open a panel
    /// stretching far to the LEFT of the notch — the island appeared to lurch
    /// sideways instead of growing out of the notch. Centring it means the
    /// panel shares the notch's own midline with the compact bar it grew from,
    /// so the expansion is a symmetric stretch: `IslandMotion` reads it as an
    /// ordinary `expand` and it springs open exactly like the dashboard.
    public var petPanelFrame: CGRect { skinFrame }

    /// The settings panel: a header, three groups of feature tiles, the
    /// weather card and a footer — tall enough to show them all without
    /// scrolling on a laptop display (it still scrolls on a short screen).
    public var settingsFrame: CGRect {
        panel(width: min(screenWidth * 0.32, 460), height: min(740, screenHeight - 40))
    }

    /// The teleprompter, reading: wide enough for a comfortable line length at
    /// the reading size, and just tall enough for a few lines plus the control
    /// bar. Deliberately NOT a tall page — the point of a notch teleprompter is
    /// that it sits above your work rather than covering it.
    public var teleprompterFrame: CGRect {
        panel(width: min(screenWidth * 0.40, 560), height: 196)
    }

    /// The teleprompter, composing: the same width, taller for the editor.
    public var teleprompterComposeFrame: CGRect {
        panel(width: min(screenWidth * 0.40, 560), height: 304)
    }

    /// The camera preview: a 16:9 picture under the notch strip, plus its
    /// control bar. Sized from the picture so the preview is never letterboxed.
    public func cameraFrame(expanded: Bool) -> CGRect {
        let width = expanded
            ? min(screenWidth * 0.46, 660)
            : min(screenWidth * 0.26, 380)
        let picture = (width - CameraLayout.horizontalInset * 2) * 9 / 16
        return panel(width: width, height: (notchFrame.height + CameraLayout.chromeHeight + picture).rounded())
    }

    /// The file-sharing drop surface: wide enough to be an easy drop target,
    /// tall enough for the badge, file name and the destination row beneath the
    /// notch inset (32pt notch + 44 badge + 16 + 20 text + 16 + 52 buttons).
    public var fileDropFrame: CGRect {
        panel(width: min(screenWidth * 0.30, 460), height: 210)
    }

    /// The union of every surface the island can become.
    ///
    /// The window is sized to this once and then never resized. AppKit resizes
    /// a window instantly, with no animation, so a frame that changed on every
    /// hover would make the island jump even while its content animated —
    /// exactly the abrupt feel a fixed envelope removes. Clicks pass through
    /// everywhere outside the island itself, so the extra area costs nothing.
    public var envelopeFrame: CGRect {
        let frames = [
            notchFrame,
            // The content-driven surfaces are sized to the generous ceiling, so
            // the window is wide enough for the island at its widest without
            // ever resizing mid-animation. The island itself stays snug.
            wingsBar(sideWidth: Self.maxContentOverhang),
            compactBar(lead: Self.maxContentOverhang, trail: Self.maxContentOverhang),
            expandedFrame,
            interactiveFrame,
            appPanelFrame(height: Self.appPanelMaxHeight),
            trayFrame,
            meetingFrame,
            skinFrame,
            settingsFrame,
            fileDropFrame,
            teleprompterComposeFrame,
            cameraFrame(expanded: true),
            neoPanelFrame(page: NeoPanelLayout.maxPageSize(screen: CGSize(width: screenWidth, height: screenHeight))),
        ]
        guard let first = frames.first else { return notchFrame }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// The resting shapes of the island.
public enum IslandState: String, CaseIterable, Equatable {
    /// Invisible — the island is exactly the notch.
    case idle
    /// The sideways hover peek: a notch-height bar stretching left and right.
    case wings
    /// A small pill hugging the notch.
    case compact
    /// The full information surface.
    case expanded
    /// The dashboard a click opens.
    case interactive
    /// The frontmost app's own panel (a browser, a coding agent).
    case appPanel
    /// The clipboard Tray browser.
    case tray
    /// A live call's control panel.
    case meeting
    /// The frontmost-app skin.
    case skin
    /// The settings panel.
    case settings
    /// The file-sharing drop surface.
    case fileDrop
    /// The teleprompter, scrolling a script.
    case teleprompter
    /// The teleprompter, being written or pasted into.
    case teleprompterCompose
    /// The camera preview.
    case camera
    /// The camera preview, larger.
    case cameraExpanded
    /// NEO's panel: its whole chat, hanging down from the notch.
    case neoPanel
}
