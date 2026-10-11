import AppKit
import NotchHubCore

/// Measures how much room the island's content needs, so the black surface can
/// grow to fit it and collapse when there is less.
///
/// The wings and the compact bar are CONTENT-DRIVEN — this is the measuring
/// pass. It walks the exact items the views will draw (app icon, status glyphs,
/// the music visualizer, a track title) and returns an `IslandContentSize`. The
/// coordinator feeds that into `NotchGeometry`, which sizes the island's frame
/// to match. Nothing here is a hardcoded "how big should it be" — the numbers
/// come from the content itself.
enum IslandMetrics {

    /// Gap between the app icon and its strip label.
    static let stripLabelSpacing: CGFloat = 6
    /// The widest a strip label may grow before it truncates.
    static let stripLabelMaxWidth: CGFloat = 96
    /// The agent readout's flame glyph size and its gap to the count.
    static let agentGlyphWidth: CGFloat = 10
    static let agentSpacing: CGFloat = 4

    /// Measures the hover wings: each side fits its own content, so a nearly
    /// empty left wing stays short beside a busy right one.
    /// `petSlot` is extra room at the right wing's end for the pixel pet.
    static func wings(_ status: WingStatus, petSlot: CGFloat = 0) -> (lead: CGFloat, trail: CGFloat) {
        var left: CGFloat = 0
        if status.left != nil || status.strip != nil {
            left = DesignTokens.wingInset * 2
            if status.left != nil { left += DesignTokens.iconSizeWingApp }
            if let strip = status.strip {
                left += (status.left != nil ? stripLabelSpacing : 0) + min(textWidth(strip.label), stripLabelMaxWidth)
            }
        }

        let right: CGFloat
        switch status.strip?.trailing {
        case .browserControls?:
            right = DesignTokens.wingInset * 2 + WingControlLayout.controlsWidth
        case let .agent(tokens, _)?:
            right = DesignTokens.wingInset * 2 + agentGlyphWidth + agentSpacing + textWidth(tokens)
        case .status?, nil:
            var widths: [CGFloat] = []
            if status.musicPlaying {
                widths.append(musicVisualizerWidth)
            }
            for item in status.right {
                widths.append(glyphWidth(item))
            }
            var total = DesignTokens.wingInset * 2
            if !widths.isEmpty {
                // space8 separates the leading inset spacer, each glyph and the
                // trailing spacer: one gap more than there are glyphs.
                total += widths.reduce(0, +) + DesignTokens.space8 * CGFloat(widths.count + 1)
            }
            right = total
        }

        return (max(DesignTokens.wingMinWidth, left), max(DesignTokens.wingMinWidth, right + petSlot))
    }

    /// Measures the compact bar: a snug lead wing for the glyph, and a trail
    /// wing sized to the live text it will draw.
    ///
    /// The measurement must mirror the view EXACTLY — including the gap
    /// between the text and its detail — or the drawn content overflows the
    /// frame and the last word is truncated.
    static func compact(_ activity: Activity, petSlot: CGFloat = 0) -> IslandContentSize {
        var lead = DesignTokens.compactInset
            + DesignTokens.iconSizeCompact
            + DesignTokens.compactInset

        var trail = DesignTokens.compactInset
        if activity.kind == .music {
            // Music shows a 28pt square artwork thumbnail + the track title on
            // the lead (left) side.
            // Capped at maxCompactMusicTextWidth so long titles don't stretch the left wing
            // into an unsightly asymmetric shape across the menu bar; titles exceeding this
            // smoothly marquee/carousel scroll.
            lead = DesignTokens.compactInset + 28 + DesignTokens.compactInset
            if let text = activity.compactText {
                let boundedTextWidth = min(textWidth(text), maxCompactMusicTextWidth)
                lead += DesignTokens.space8 + boundedTextWidth
            }
            // Only the visualizer on the trail (right) side.
            trail += musicVisualizerWidth
        } else if activity.kind == .identifiedSong {
            lead = DesignTokens.compactInset + 28 + DesignTokens.space8
                + min(textWidth(activity.title), maxCompactMusicTextWidth)
            if let detail = activity.compactDetail {
                trail += min(textWidth(detail), 92)
            }
        } else if activity.kind == .songRecognition {
            lead += DesignTokens.space8 + min(textWidth(activity.title), maxCompactMusicTextWidth)
            trail += musicVisualizerWidth
        } else if activity.kind == .meeting {
            // The call timer beside the glyph; mute and leave on the trail.
            lead += DesignTokens.space8 + textWidth("00:00:00")
            trail += MeetingControlLayout.compactControlsWidth
        } else if let text = activity.compactText {
            trail += textWidth(text)
            if let detail = activity.compactDetail {
                trail += DesignTokens.space4 + textWidth(detail)
            }
        }
        trail += DesignTokens.compactInset

        // Never wider than the island may grow: the frame clamps there, and a
        // wing measured wider would push its text under the pet.
        let limit = NotchGeometry.maxContentOverhang
        return IslandContentSize(compactLead: min(lead, limit), compactTrail: min(trail + petSlot, limit), wingSide: 0)
    }

    /// The width of one status glyph: a real app icon is large, an SF Symbol is
    /// the smaller status size.
    private static func glyphWidth(_ item: WingItem) -> CGFloat {
        guard item.iconData == nil else { return DesignTokens.iconSizeWingApp }
        if let cached = symbolWidths[item.symbol] { return cached }
        // SF Symbols are wider than their point size (a charging battery is
        // nearly twice as wide), so measure the glyph the view will draw.
        let configuration = NSImage.SymbolConfiguration(pointSize: DesignTokens.iconSizeWingStatus, weight: .semibold)
        let measured = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.size.width
        let width = ceil(max(measured ?? DesignTokens.iconSizeWingStatus, DesignTokens.iconSizeWingStatus))
        symbolWidths[item.symbol] = width
        return width
    }

    private static var symbolWidths: [String: CGFloat] = [:]

    /// The music visualizer's own width. Horizontally extended per user request.
    static var musicVisualizerWidth: CGFloat { 48 }

    /// Maximum text width for track names in the compact notch bar.
    /// Keeps the island proportional and prevents long titles from sprawling across the menu bar.
    static var maxCompactMusicTextWidth: CGFloat { 110 }

    /// Measures a string in the rounded system font, matching how the compact
    /// label renders, so the island sizes itself to the text it will draw.
    ///
    /// Rounded UP: SwiftUI lays text out on whole pixels, so a fractional
    /// measurement of e.g. 40.4pt would allocate 40 and truncate. Ceiling it
    /// guarantees the frame is never narrower than the glyphs.
    static func textWidth(_ string: String) -> CGFloat {
        let base = NSFont.systemFont(ofSize: DesignTokens.compactFontSize, weight: .semibold)
        let font: NSFont
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: DesignTokens.compactFontSize) {
            font = rounded
        } else {
            font = base
        }
        let width = (string as NSString).size(withAttributes: [.font: font]).width
        return ceil(width)
    }
}
