import CoreGraphics
import Foundation

/// The "NEO is listening" mark beside the pet: whether it shows, and for how
/// long it carries its word.
///
/// While NEO's held state is `listening` — its microphone is live — a tiny
/// voice meter sits on the pet's inner side, toward the notch. For the first
/// `labelDuration` after listening starts the word "Listening" stands beside
/// it; then only the bars remain. The moment the state leaves `listening`
/// the mark is gone. With NEO idle or away there is no mark at all, and the
/// island is exactly what it was.
///
/// Pure and clock-driven like `NeoPresenceModel`: the app feeds it NEO's held
/// state, and `nextWake(at:)` says when the word will step aside, so nothing
/// polls.
public struct NeoListeningIndicator: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        /// NEO is not listening: nothing is drawn, nothing is reserved.
        case hidden
        /// Listening just started: the bars and the word.
        case labelled
        /// Still listening: the bars alone.
        case bars
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
        return now.timeIntervalSince(since) < Self.labelDuration ? .labelled : .bars
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
    /// notch, peeking, mid-game), where there is no inner side to stand on.
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
                slot: NeoListeningLayout.slot(showsLabel ? .labelled : .bars, labelWidth: label),
                since: since
            )
        case .fits:
            return NeoListeningMark(showsLabel: false, labelWidth: 0, slot: 0, since: since)
        }
    }
}

/// The listening mark in one island shape.
public struct NeoListeningMark: Equatable, Sendable {
    /// Whether the word stands beside the bars.
    public var showsLabel: Bool
    /// The word's width (0 without it).
    public var labelWidth: CGFloat
    /// Room the mark takes on the pet's inner side: how far the idle dock,
    /// the wings and the compact bar grow (on the pet's side only), and what
    /// the expanded island's content gives up. `0` where the mark fits in
    /// room that is already there.
    public var slot: CGFloat
    /// When listening began — the bars' procedural motion runs from here.
    public var since: Date

    public init(showsLabel: Bool, labelWidth: CGFloat, slot: CGFloat, since: Date) {
        self.showsLabel = showsLabel
        self.labelWidth = labelWidth
        self.slot = slot
        self.since = since
    }

    /// The drawn width: the bars, and the word with its gap.
    public var width: CGFloat {
        NeoListeningLayout.markWidth + (showsLabel ? NeoListeningLayout.gap + labelWidth : 0)
    }
}

/// The listening mark's measurements and where it sits.
///
/// `[ notch ][ inset ][ Listening ][ bars ][ pet ][ inset ]` — the bars stay
/// against the pet, the word on the notch's side of them, so when the word
/// leaves the bars do not move relative to the pet.
public enum NeoListeningLayout {

    /// Thin rounded bars, like a voice meter.
    public static let barCount = 4
    public static let barWidth: CGFloat = 2
    public static let barSpacing: CGFloat = 2
    /// The tallest a bar gets.
    public static let markHeight: CGFloat = 12
    /// The shortest a bar gets: a dot, never nothing.
    public static let minBarHeight: CGFloat = 3

    /// The bars' total width: 14 pt.
    public static var markWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    }

    /// Space between the bars and the pet, and between the word and the bars.
    public static let gap: CGFloat = 4

    /// The widest the word may be drawn; a longer one truncates.
    public static let maxLabelWidth: CGFloat = 50

    /// What the bars alone add on the pet's side: 18 pt.
    public static var barsSlot: CGFloat { markWidth + gap }

    /// The most the mark ever adds: the bars and the word at its widest, 72 pt.
    public static var maxSlot: CGFloat { barsSlot + gap + maxLabelWidth }

    /// Room the mark needs on the pet's inner side in a phase.
    public static func slot(_ phase: NeoListeningIndicator.Phase, labelWidth: CGFloat) -> CGFloat {
        switch phase {
        case .hidden: return 0
        case .bars: return barsSlot
        case .labelled: return barsSlot + gap + min(max(0, labelWidth), maxLabelWidth)
        }
    }

    /// How a shape makes room for the mark.
    public enum Room: Equatable, Sendable {
        /// The shape gives the mark its own room on the pet's side: the idle
        /// dock, the wings and the compact bar grow by the slot, the expanded
        /// island's content gives it up. The word shows here.
        case grows
        /// The bars fit in room that is already there (the notch strip of the
        /// dashboard, an app panel, a call's controls): nothing grows, and
        /// there is no word — beside the pet it would reach under the notch.
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

    /// The mark's rectangle in the island's coordinates (top-left origin), on
    /// the pet's inner side — toward the notch — and centred on the pet.
    public static func frame(_ mark: NeoListeningMark, beside pet: PetLayout.Placement) -> CGRect {
        let width = mark.width
        let edge = petEdge(beside: pet)
        let x = pet.anchor == .leading ? edge.x : edge.x - width
        return CGRect(x: x, y: edge.y, width: width, height: markHeight)
    }

    /// Where the mark meets the pet: the x of its pet-facing side and its
    /// top, in the island's coordinates. The mark grows away from here toward
    /// the notch, so this point does not depend on whether the word shows.
    public static func petEdge(beside pet: PetLayout.Placement) -> CGPoint {
        CGPoint(
            x: pet.anchor == .leading ? pet.origin.x + pet.size + gap : pet.origin.x - gap,
            y: pet.origin.y + ((pet.size - markHeight) / 2).rounded(.down)
        )
    }

    // MARK: - The bars' motion

    /// The bars at rest (reduced motion): a still meter, no pulsing.
    public static let restingLevels: [Double] = [0.45, 0.9, 0.65, 0.35]

    /// The quietest a moving bar gets.
    public static let minLevel: Double = 0.25

    /// One bar's level (`minLevel`…1) at `time` seconds into listening.
    ///
    /// PROCEDURAL: NEO's core reports that it is listening, not how loud the
    /// room is, so the bars move to their own slow rhythm — two unhurried
    /// sines per bar, out of step with their neighbours — and claim nothing
    /// about the microphone's level. They say "the mic is live", no more.
    public static func level(bar index: Int, at time: TimeInterval) -> Double {
        let i = ((index % barCount) + barCount) % barCount
        let slow = [1.10, 1.45, 1.25, 0.95][i]
        let quick = [2.30, 1.90, 2.70, 2.10][i]
        let phase = Double(i) * 1.7
        let a = 0.5 + 0.5 * sin(2 * .pi * slow * time + phase)
        let b = 0.5 + 0.5 * sin(2 * .pi * quick * time + phase * 0.6 + 0.9)
        return min(1, max(minLevel, minLevel + (1 - minLevel) * (0.62 * a + 0.38 * b)))
    }

    /// A bar's height for a level, in whole half-points so it stays crisp.
    public static func barHeight(level: Double) -> CGFloat {
        let raw = CGFloat(min(1, max(0, level))) * markHeight
        return min(markHeight, max(minBarHeight, (raw * 2).rounded() / 2))
    }
}
