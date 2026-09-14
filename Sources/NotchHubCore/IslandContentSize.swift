import CoreGraphics

/// How much room the island's CONTENT needs on each side of the notch.
///
/// The wings and the compact bar are content-driven: the island measures what
/// it is about to draw — the app icon, the status glyphs, a track title — and
/// grows its black surface to fit, then collapses back when there is less to
/// show. Nothing here is a fixed "how big the island should be" number; these
/// are the widths the measuring pass reported.
///
/// Pure and `Equatable` so the sizing can be unit-tested without a display.
public struct IslandContentSize: Equatable, Sendable {

    /// How far the compact bar reaches to the LEFT of the notch edge — just
    /// enough for the activity's glyph and its inset.
    public var compactLead: CGFloat
    /// How far the compact bar reaches to the RIGHT of the notch edge — enough
    /// for the title and value, however long they are.
    public var compactTrail: CGFloat
    /// How wide the RIGHT hover wing is — and the left one too, unless
    /// `wingLead` says otherwise.
    public var wingSide: CGFloat
    /// How wide the LEFT hover wing is. Each wing fits its own content, so a
    /// lone app icon on the left doesn't get the width of a full right wing.
    /// `nil` makes the wings equal.
    public var wingLead: CGFloat? = nil
    /// The height a content-driven panel needs (an app panel with extra rows).
    /// `nil` uses the panel's standard height.
    public var panelHeight: CGFloat? = nil
    /// The IDLE island's home for the pixel pet beside the notch — which side,
    /// and how far it reaches out. `nil` (no pet dock) keeps idle exactly the
    /// notch.
    public var petDock: PetDock? = nil
    /// Where the pet's panel hangs from: the island edge beside the pet when it
    /// was clicked, in screen coordinates. `nil` centres it.
    public var panelAnchor: PetPanelAnchor? = nil

    public init(compactLead: CGFloat, compactTrail: CGFloat, wingSide: CGFloat) {
        self.compactLead = max(0, compactLead)
        self.compactTrail = max(0, compactTrail)
        self.wingSide = max(0, wingSide)
    }

    /// The resting sizes, used when nothing has been measured yet (and as the
    /// fallback for the pure-geometry tests).
    public static let `default` = IslandContentSize(
        compactLead: NotchGeometry.compactLeadOverhang,
        compactTrail: NotchGeometry.compactTrailOverhang,
        wingSide: NotchGeometry.wingWidth
    )
}
