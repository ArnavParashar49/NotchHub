import SwiftUI

/// The NotchHub design system.
///
/// Apple Dynamic Island language: near-black, high contrast, generous spacing,
/// sharp rectangular corners, SF typography, no borders, no gradients, no
/// clutter. Every container, row, chip, panel, badge, progress track and
/// search field uses square corners to match the notch's hard-edged
/// industrial language. Status dots may remain round when they read as
/// deliberate glyphs (a live "on air" pip).
/// The idle state is deliberately invisible — the island *is* the notch.
public enum DesignTokens {

    // MARK: - Palette

    /// The island's fill — true black, matching the notch cutout exactly.
    ///
    /// It must be the same black the notch reads as, or the island shows up as
    /// a lighter rectangle hanging off the notch instead of an extension of it.
    public static let islandFill = Color.black
    /// Slightly lifted fill for nested chips inside the island.
    public static let chipFill = Color.white.opacity(0.08)
    /// The capsule behind the transport buttons: a quiet raised surface.
    public static let controlClusterFill = Color.white.opacity(0.10)
    /// The capsule's hairline, so it reads as a button group on black.
    public static let controlClusterStroke = Color.white.opacity(0.16)
    /// The play/pause puck: solid white so it is the anchor of the cluster.
    public static let controlPrimaryFill = Color.white
    /// The glyph on the solid play/pause puck — black for contrast.
    public static let controlPrimaryGlyph = Color.black
    /// Primary text — full white for maximum contrast on black.
    public static let textPrimary = Color.white
    /// Secondary text — quiet, never competing with the primary line.
    public static let textSecondary = Color.white.opacity(0.62)
    /// Tertiary text — timestamps, units, hints.
    public static let textTertiary = Color.white.opacity(0.38)
    /// The single accent. Used sparingly: progress, active state, live dots.
    public static let accent = Color(red: 0.353, green: 0.784, blue: 0.980)
    /// Warning accent for low battery and recording.
    public static let warning = Color(red: 1.0, green: 0.584, blue: 0.0)
    /// Live/recording red.
    public static let live = Color(red: 1.0, green: 0.271, blue: 0.227)
    /// The Tray's selected-row wash — a whisper of light, never a fill.
    public static let rowSelected = Color.white.opacity(0.10)
    /// The Tray's hairline between rows.
    public static let rowSeparator = Color.white.opacity(0.06)
    /// A quiet fill for panel footers and search fields.
    public static let fieldFill = Color.white.opacity(0.06)
    /// Tint for a live call's "on air" state.
    public static let onAir = Color(red: 0.30, green: 0.85, blue: 0.46)

    // MARK: - Panel geometry
    
    /// Corner radius for the large panel surfaces (Tray, meetings).
    /// Rounded: 24 — the panels match the island's premium rounded language.
    public static let radiusPanel: CGFloat = 24
    /// Radius for rows and list items inside a panel.
    public static let radiusRow: CGFloat = 12

    // MARK: - Geometry

    /// Corner radius for the expanded island.
    public static let radiusIsland: CGFloat = 22
    /// Radius for the island's BOTTOM corners only.
    ///
    /// The bottom corners carry a convex curve, giving the island its
    /// pill-like base. The TOP corners flare into the screen's top edge like
    /// the physical notch's (`radiusNotchTopFlare`). Authored against the
    /// notch's 32pt height; the shape scales it as the island grows.
    public static let radiusIslandBottom: CGFloat = 18
    /// Radius for the wings' OUTER bottom corners only.
    ///
    /// The wings are a notch-height bar, so the curve has to stay tight — a
    /// larger value would turn the ends into a pill and break the bar away
    /// from the notch's straight sides. The outer TOP corners flare like the
    /// island's.
    public static let radiusWingBottom: CGFloat = 14
    /// The PHYSICAL notch's bottom-corner radius on MacBook displays. Where the
    /// island continues the hardware notch (the pixel pet's idle dock), its
    /// outer corner uses this so both ends of the black shape match.
    public static let radiusPhysicalNotchBottom: CGFloat = 12
    /// The PHYSICAL notch's top flare: where the notch meets the top of the
    /// screen its sides sweep outward in a small concave curve (the menu bar's
    /// corner beside it looks rounded). Every island shape flares the same way,
    /// so it reads as the notch itself.
    public static let radiusNotchTopFlare: CGFloat = 6
    /// Corner radius for the compact pill.
    public static let radiusCompact: CGFloat = 16
    /// Corner radius for small chips and control buttons.
    public static let radiusChip: CGFloat = 8
    /// Corner radius for the progress track.
    public static let radiusTrack: CGFloat = 4

    // MARK: - Spacing

    public static let space2: CGFloat = 2
    public static let space4: CGFloat = 4
    public static let space6: CGFloat = 6
    public static let space8: CGFloat = 8
    public static let space10: CGFloat = 10
    public static let space12: CGFloat = 12
    public static let space16: CGFloat = 16
    public static let space20: CGFloat = 20
    /// Horizontal inset of island content from the island edge.
    public static let contentInset: CGFloat = 18
    /// Horizontal inset of compact-bar content from the bar's outer edge.
    ///
    /// The compact bar is only notch-height, so the inset is tighter than the
    /// expanded panel's — enough to keep the glyph off the rounded corner
    /// without eating the wing.
    public static let compactInset: CGFloat = 14
    /// Horizontal inset of a wing's content from the bar's outer edge.
    public static let wingInset: CGFloat = 16
    /// The smallest a hover wing may be, so a nearly-empty wing still reads as
    /// an intentional bar rather than a sliver.
    public static let wingMinWidth: CGFloat = 48

    // MARK: - Typography

    /// Primary line — the one thing the island is telling you.
    public static let titleFont = Font.system(size: 13, weight: .semibold, design: .rounded)
    /// Secondary line — artist, device, context.
    public static let subtitleFont = Font.system(size: 11, weight: .medium, design: .rounded)
    /// Numeric readouts — timers, percentages. Monospaced so digits don't jitter.
    public static let numericFont = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    /// Compact-state label.
    public static let compactFont = Font.system(size: compactFontSize, weight: .semibold, design: .rounded)
    /// The compact label's point size — shared by the font and the text-measuring
    /// pass, so the island sizes itself to the text it will actually render.
    public static let compactFontSize: CGFloat = 11
    /// The "+N" stack badge.
    public static let badgeFont = Font.system(size: 9, weight: .bold, design: .rounded)

    // MARK: - Iconography

    public static let iconSize: CGFloat = 15
    /// The activity glyph in the compact bar. Sized to read clearly at notch
    /// height — the bar is short, so a timid icon disappears.
    public static let iconSizeCompact: CGFloat = 20
    public static let iconSizeLarge: CGFloat = 20
    /// The frontmost app's real icon in the left wing. Larger than a status
    /// glyph so the app you are in is unmistakable at a glance.
    public static let iconSizeWingApp: CGFloat = 24
    /// A status glyph in the right wing.
    public static let iconSizeWingStatus: CGFloat = 13

    // MARK: - Motion

    //
    // The island moves like one body of liquid: the black surface is driven by
    // springs chosen from the geometry change (`IslandMotion`), content is
    // clipped to the surface and blur-fades around it, and nothing snaps.
    //
    // Rules that keep it smooth:
    // - ONE transaction per change. `renderIsland` is the only caller of
    //   `withAnimation` for the island; nested `withAnimation` calls override
    //   each other, which is how every collapse used to ride the morph spring.
    // - Shrinking is CRITICALLY DAMPED (dampingFraction 1). Any undershoot makes
    //   the surface briefly smaller than its content, which reads as a snap.
    // - Every spring carries a `blendDuration`, so an interrupted motion (hover
    //   out mid-expand) bends into the new target instead of kinking.
    // - Old content leaves fast; new content arrives after the shape has
    //   started moving. The surface never fades while it is still shrinking.

    /// Emerging from the notch (idle → wings / compact): a soft, quick pour
    /// outward with a trace of give.
    public static let springPeek = Animation.spring(response: 0.40, dampingFraction: 0.84, blendDuration: 0.12)
    /// Growing into a larger surface: a fluid stretch that settles with a
    /// whisper of overshoot, like liquid finding its level.
    public static let springExpand = Animation.spring(response: 0.50, dampingFraction: 0.82, blendDuration: 0.14)
    /// Shrinking to a smaller visible surface: critically damped, so it
    /// decelerates continuously into place and never undershoots.
    public static let springCollapse = Animation.spring(response: 0.50, dampingFraction: 1.0, blendDuration: 0.14)
    /// Draining back into the notch: a touch longer and critically damped, so
    /// the black flows home rather than being yanked.
    public static let springRetract = Animation.spring(response: 0.56, dampingFraction: 1.0, blendDuration: 0.14)
    /// Same footprint, new proportions or content (a bar widening for a longer
    /// readout, one activity replacing another).
    public static let springMorph = Animation.spring(response: 0.44, dampingFraction: 0.92, blendDuration: 0.12)
    /// Small in-place value changes (progress tracks, meters).
    public static let springSettle = springMorph
    /// Numeric: monospaced digits ride a very stiff spring to avoid jitter.
    public static let springNumeric = Animation.spring(response: 0.15, dampingFraction: 1.0)

    /// The spring for a motion, or `nil` when nothing visible moves.
    public static func animation(for motion: IslandMotion) -> Animation? {
        switch motion {
        case .none: return nil
        case .peek: return springPeek
        case .expand: return springExpand
        case .collapse: return springCollapse
        case .retract: return springRetract
        case .morph: return springMorph
        }
    }

    /// Outgoing content: gone quickly, before the surface has moved far, so it
    /// never lingers against a shape that no longer fits it.
    public static let contentOut = Animation.easeOut(duration: 0.14)
    /// Incoming content: waits for the surface to start opening, then flows in.
    public static let contentIn = Animation.easeOut(duration: 0.30).delay(0.10)
    /// How blurred content is at the start of its entrance / end of its exit.
    public static let contentBlurRadius: CGFloat = 8
    /// How small content is at the start of its entrance / end of its exit.
    public static let contentScale: CGFloat = 0.94

    /// How long after a retract begins the surface starts fading. By then the
    /// critically damped retract is ~96% home, hidden behind the physical notch;
    /// fading earlier turned the shrinking shape translucent grey.
    public static let retractFadeDelay: TimeInterval = 0.44
    /// The final fade of the (by now notch-sized) surface.
    public static let surfaceFade = Animation.easeOut(duration: 0.18)

    // MARK: - Shadow
    //
    // Deliberately EMPTY: the island is meant to read as the physical notch —
    // a crisp, flat, matte-black shape with a sharp hard border, exactly like
    // the hardware cutout. A drop shadow or glow is what makes it look like a
    // floating software widget instead, so there is none.
}
