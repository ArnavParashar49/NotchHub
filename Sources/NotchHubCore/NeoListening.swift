import CoreGraphics
import Foundation

/// The "NEO is listening" mark: whether it shows, and for how long it
/// carries its word.
///
/// While NEO's held state is `listening` — its microphone is live — a soft
/// halo breathes BEHIND the pet, as if it were lit up and paying attention.
/// For the first `labelDuration` after listening starts the word "Listening"
/// stands beside the pet, on its inner side (toward the notch); then the word
/// leaves and only the glow remains — taking no room at all: the island is
/// exactly as wide as it is without NEO. The moment the state leaves
/// `listening` the glow fades. With NEO idle or away there is no mark at all,
/// and the island is exactly what it was.
///
/// Pure and clock-driven like `NeoPresenceModel`: the app feeds it NEO's held
/// state, and `nextWake(at:)` says when the word will step aside, so nothing
/// polls.
public struct NeoListeningIndicator: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        /// NEO is not listening: nothing is drawn, nothing is reserved.
        case hidden
        /// Listening just started: the glow behind the pet, and the word
        /// beside it.
        case labelled
        /// Still listening: the glow alone — no room taken.
        case glow
    }

    /// How long the word stays after listening starts.
    public static let labelDuration: TimeInterval = 1.5
    /// The word itself.
    public static let label = "Listening"
    /// What assistive technology reads for the mark.
    public static var accessibilityLabel: String { "\(PetIdentity.name) is listening" }

    /// When this stretch of listening began; `nil` while NEO is not listening.
    public private(set) var since: Date?

    public init() {}

    /// Takes whether NEO is listening right now (its held state, and its core
    /// connected). Returns whether the mark appeared or disappeared. A stretch
    /// that is still going keeps its start: only a NEW stretch shows the word
    /// again.
    @discardableResult
    public mutating func update(listening: Bool, at now: Date) -> Bool {
        if listening {
            guard since == nil else { return false }
            since = now
            return true
        }
        guard since != nil else { return false }
        since = nil
        return true
    }

    /// Takes NEO's presence: the mark shows only while its core is connected
    /// and its held state is `listening`.
    @discardableResult
    public mutating func update(presence: NeoPresenceModel, at now: Date) -> Bool {
        update(listening: presence.isConnected && presence.state == .listening, at: now)
    }

    public func phase(at now: Date) -> Phase {
        guard let since else { return .hidden }
        return now.timeIntervalSince(since) < Self.labelDuration ? .labelled : .glow
    }

    /// When the word steps aside on its own; `nil` once it has, or while the
    /// mark is hidden.
    public func nextWake(at now: Date) -> Date? {
        guard let since else { return nil }
        let end = since.addingTimeInterval(Self.labelDuration)
        return end > now ? end : nil
    }

    /// The mark as an island shape draws it, or `nil` where it does not show:
    /// while hidden, on surfaces the pet steps aside for, and on the idle dock
    /// while the pet is not standing at its spot (`petAtHome` — hiding in the
    /// notch, peeking, mid-game), where there is no pet to light.
    ///
    /// `labelWidth` is the word's measured width in the compact font.
    public func mark(for state: IslandState, at now: Date, labelWidth: CGFloat, petAtHome: Bool = true) -> NeoListeningMark? {
        guard let since else { return nil }
        guard let room = NeoListeningLayout.room(in: state) else { return nil }
        if state == .idle, !petAtHome { return nil }
        let label = min(max(0, labelWidth), NeoListeningLayout.maxLabelWidth)
        switch room {
        case .grows:
            let showsLabel = phase(at: now) == .labelled && label > 0
            return NeoListeningMark(
                showsLabel: showsLabel,
                labelWidth: showsLabel ? label : 0,
                slot: NeoListeningLayout.slot(showsLabel ? .labelled : .glow, labelWidth: label),
                since: since
            )
        case .fits:
            return NeoListeningMark(showsLabel: false, labelWidth: 0, slot: 0, since: since)
        }
    }
}

/// The listening mark in one island shape.
public struct NeoListeningMark: Equatable, Sendable {
    /// Whether the word stands beside the pet.
    public var showsLabel: Bool
    /// The word's width (0 without it).
    public var labelWidth: CGFloat
    /// Room the mark takes on the pet's inner side: how far the idle dock,
    /// the wings and the compact bar grow (on the pet's side only), and what
    /// the expanded island's content gives up. Only the word takes room:
    /// `0` once it has gone — the glow sits behind the pet — and on the
    /// fixed-strip surfaces, which never show the word.
    public var slot: CGFloat
    /// When listening began — the glow's breathing runs from here.
    public var since: Date

    public init(showsLabel: Bool, labelWidth: CGFloat, slot: CGFloat, since: Date) {
        self.showsLabel = showsLabel
        self.labelWidth = labelWidth
        self.slot = slot
        self.since = since
    }
}

/// The listening mark's measurements, where it sits, and how it breathes.
///
/// `[ notch ][ inset ][ Listening ][ gap ][ pet ][ inset ]` — the glow is
/// centred on the pet, behind it; the word stands on the notch's side of the
/// pet, and when it leaves nothing else moves.
public enum NeoListeningLayout {

    // MARK: - The glow

    /// How far the halo reaches past the pet on every side: the glow is the
    /// pet's size + 6 pt (22 pt around the 16-pt fox of the notch strip,
    /// 38 pt around the 32-pt fox of the expanded island).
    public static let glowSpread: CGFloat = 3

    /// The halo's diameter around a pet `petSize` points across.
    public static func glowDiameter(petSize: CGFloat) -> CGFloat {
        petSize + glowSpread * 2
    }

    /// How much the halo is blurred, per point of the pet's pixel scale — it
    /// must read as light, not as a disc.
    public static let glowBlur: CGFloat = 2

    /// One full breath: dim → bright → dim.
    public static let breathPeriod: TimeInterval = 1.6
    /// The halo's opacity at the bottom and the top of a breath.
    public static let glowOpacityRange: ClosedRange<Double> = 0.35...0.75
    /// The halo's scale at the bottom and the top of a breath.
    public static let glowScaleRange: ClosedRange<CGFloat> = 0.92...1.06
    /// With Reduce Motion: a steady glow, mid-breath, at its drawn size.
    public static let steadyOpacity: Double = 0.55
    public static let steadyScale: CGFloat = 1

    /// Where the breath is (0 = dimmest, 1 = brightest) `time` seconds into
    /// listening: a sine, so it eases in and out of both ends. It starts
    /// half-way and rising — the halo blooms to its brightest 0.4 s in, as it
    /// finishes fading in — and is dimmest at 1.2 s, then every 1.6 s.
    ///
    /// PROCEDURAL: NEO's core reports that it is listening, not how loud the
    /// room is, so the glow keeps its own slow rhythm and claims nothing
    /// about the microphone's level.
    public static func breath(at time: TimeInterval) -> Double {
        0.5 + 0.5 * sin(2 * .pi * time / breathPeriod)
    }

    public static func glowOpacity(breath: Double) -> Double {
        let b = min(1, max(0, breath))
        return glowOpacityRange.lowerBound + (glowOpacityRange.upperBound - glowOpacityRange.lowerBound) * b
    }

    public static func glowScale(breath: Double) -> CGFloat {
        let b = CGFloat(min(1, max(0, breath)))
        return glowScaleRange.lowerBound + (glowScaleRange.upperBound - glowScaleRange.lowerBound) * b
    }

    /// The halo's square in the island's coordinates (top-left origin),
    /// centred on the pet. At the top of a breath it is drawn `scale` times
    /// this, about the same centre.
    public static func glowFrame(behind pet: PetLayout.Placement, scale: CGFloat = 1) -> CGRect {
        let side = glowDiameter(petSize: pet.size) * scale
        let inset = (pet.size - side) / 2
        return CGRect(x: pet.origin.x + inset, y: pet.origin.y + inset, width: side, height: side)
    }

    // MARK: - The word

    /// Space between the word and the pet (the halo's own reach, and as much
    /// again of clear black).
    public static let labelGap: CGFloat = 6

    /// The height of the word's row, centred on the pet.
    public static let labelHeight: CGFloat = 12

    /// The widest the word may be drawn; a longer one truncates.
    public static let maxLabelWidth: CGFloat = 50

    /// The most the mark ever adds: the word at its widest and its gap, 56 pt.
    public static var maxSlot: CGFloat { labelGap + maxLabelWidth }

    /// Room the mark needs on the pet's inner side in a phase: the word and
    /// its gap while it shows, and NOTHING once it has gone.
    public static func slot(_ phase: NeoListeningIndicator.Phase, labelWidth: CGFloat) -> CGFloat {
        switch phase {
        case .hidden, .glow: return 0
        case .labelled:
            let label = min(max(0, labelWidth), maxLabelWidth)
            return label > 0 ? labelGap + label : 0
        }
    }

    /// How a shape takes the mark.
    public enum Room: Equatable, Sendable {
        /// The shape gives the word its own room on the pet's side for its
        /// 1.5 s: the idle dock, the wings and the compact bar grow by the
        /// slot, the expanded island's content gives it up. Afterwards the
        /// shape is exactly what it is without the mark.
        case grows
        /// A fixed strip (the notch strip of the dashboard, an app panel, a
        /// call's controls): the glow only. Nothing grows, and there is no
        /// word — beside the pet it would reach under the notch.
        case fits
    }

    /// Where the mark rides: every shape the pet does. `nil` where the pet
    /// steps aside.
    public static func room(in state: IslandState) -> Room? {
        switch state {
        case .idle, .wings, .compact, .expanded: return .grows
        case .interactive, .appPanel, .meeting: return .fits
        case .tray, .settings, .fileDrop, .skin,
             .teleprompter, .teleprompterCompose, .camera, .cameraExpanded, .neoPanel:
            return nil
        }
    }

    /// The word's rectangle in the island's coordinates (top-left origin), on
    /// the pet's inner side — toward the notch — and centred on the pet.
    /// Empty (zero width) for a mark without its word.
    public static func labelFrame(_ mark: NeoListeningMark, beside pet: PetLayout.Placement) -> CGRect {
        let width = mark.showsLabel ? mark.labelWidth : 0
        let edge = labelEdge(beside: pet)
        let x = pet.anchor == .leading ? edge.x : edge.x - width
        return CGRect(x: x, y: edge.y, width: width, height: labelHeight)
    }

    /// Where the word meets the pet: the x of its pet-facing side and its
    /// top, in the island's coordinates. The word grows away from here toward
    /// the notch.
    public static func labelEdge(beside pet: PetLayout.Placement) -> CGPoint {
        CGPoint(
            x: pet.anchor == .leading ? pet.origin.x + pet.size + labelGap : pet.origin.x - labelGap,
            y: pet.origin.y + ((pet.size - labelHeight) / 2).rounded(.down)
        )
    }
}
