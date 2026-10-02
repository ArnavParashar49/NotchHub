import CoreGraphics
import Foundation

/// The "NEO is listening" mark: one pulse of light behind the pet, each time
/// NEO starts to listen.
///
/// When NEO's held state becomes `listening` — its microphone is live — a
/// soft halo swells in BEHIND the pet, peaks, and fades fully out: ONE pulse,
/// `pulseDuration` long, as if the fox pricked up and lit for a moment. Then
/// nothing is drawn for the rest of that stretch of listening, however long
/// it lasts. A new stretch (the state left `listening` and came back) pulses
/// again. If listening ends mid-pulse the mark goes at once, and the view
/// finishes the fade. It takes no room at all: the island is exactly what it
/// is without NEO, always.
///
/// Pure and clock-driven like `NeoPresenceModel`: the app feeds it NEO's held
/// state, and `nextWake(at:)` says when the pulse is over, so nothing polls.
public struct NeoListeningIndicator: Equatable, Sendable {

    /// How long the one pulse lasts, from dark to dark.
    public static let pulseDuration: TimeInterval = 1.4
    /// What assistive technology reads for the mark, while the pulse shows.
    public static var accessibilityLabel: String { "\(PetIdentity.name) is listening" }

    /// When this stretch of listening began; `nil` while NEO is not listening.
    public private(set) var since: Date?
    /// When this stretch's pulse began: with the stretch — or, on the idle
    /// dock with the pet away from its spot, the moment the pet came home.
    /// `nil` while NEO is not listening, and while the pulse still waits for
    /// the pet. Set once per stretch: a stretch never pulses twice.
    public private(set) var pulseStart: Date?

    public init() {}

    /// Takes whether NEO is listening right now (its held state, and its core
    /// connected), and whether the pet stands where the glow would light it
    /// (`petInPlace`: always, except on the idle dock while it hides in the
    /// notch, peeks or plays — the pulse waits for it to come home). Returns
    /// whether anything changed: the stretch began or ended, or its pulse
    /// began. A stretch that is still going keeps its start and its one
    /// pulse: only a NEW stretch pulses again.
    @discardableResult
    public mutating func update(listening: Bool, at now: Date, petInPlace: Bool = true) -> Bool {
        guard listening else {
            guard since != nil else { return false }
            since = nil
            pulseStart = nil
            return true
        }
        var changed = false
        if since == nil {
            since = now
            changed = true
        }
        if pulseStart == nil, petInPlace {
            pulseStart = now
            changed = true
        }
        return changed
    }

    /// Takes NEO's presence: a stretch of listening runs only while its core
    /// is connected and its held state is `listening`.
    @discardableResult
    public mutating func update(presence: NeoPresenceModel, at now: Date, petInPlace: Bool = true) -> Bool {
        update(listening: presence.isConnected && presence.state == .listening, at: now, petInPlace: petInPlace)
    }

    /// Whether the pulse is showing: begun, and not yet over.
    public func isPulsing(at now: Date) -> Bool {
        guard let pulseStart, let end = pulseEnd else { return false }
        return now >= pulseStart && now < end
    }

    /// When the pulse is over: `pulseDuration` after it began.
    public var pulseEnd: Date? {
        pulseStart?.addingTimeInterval(Self.pulseDuration)
    }

    /// When the pulse ends on its own; `nil` once it has, before it has
    /// begun, and while NEO is not listening. At that instant the mark is
    /// already gone, so the app's wake-up there finds nothing left to draw.
    public func nextWake(at now: Date) -> Date? {
        guard let end = pulseEnd else { return nil }
        return end > now ? end : nil
    }

    /// The mark as an island shape draws it, or `nil` where nothing shows:
    /// NEO not listening, the pulse over (or not begun), a surface the pet
    /// steps aside for, and the idle dock while the pet is not standing at
    /// its spot (`petAtHome` — hiding in the notch, peeking, mid-game), where
    /// there is no pet to light.
    public func mark(for state: IslandState, at now: Date, petAtHome: Bool = true) -> NeoListeningMark? {
        guard let pulseStart, isPulsing(at: now) else { return nil }
        guard NeoListeningLayout.shows(in: state) else { return nil }
        if state == .idle, !petAtHome { return nil }
        return NeoListeningMark(pulseStart: pulseStart)
    }
}

/// The listening mark while its pulse shows. It is the same in every island
/// shape, and takes no room in any of them.
public struct NeoListeningMark: Equatable, Sendable {
    /// When the pulse began — the glow's curve runs from here
    /// (`NeoListeningLayout.pulse(at:)`).
    public var pulseStart: Date

    public init(pulseStart: Date) {
        self.pulseStart = pulseStart
    }
}

/// The listening glow's measurements, where it sits, and its one pulse.
///
/// The glow is centred on the pet, behind it, and nothing else moves for it.
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

    // MARK: - The pulse

    /// The whole pulse, dark to dark.
    public static var pulseDuration: TimeInterval { NeoListeningIndicator.pulseDuration }
    /// The swell: dark to the peak.
    public static let pulseRise: TimeInterval = 0.45
    /// The fade: the peak back to dark — slower than the swell.
    public static var pulseFall: TimeInterval { pulseDuration - pulseRise }

    /// The halo's opacity at the peak of the pulse.
    public static let peakOpacity: Double = 0.8
    /// The halo's scale at the two dark ends of the pulse and at its peak:
    /// it swells as it brightens and draws back in as it fades.
    public static let pulseScaleRange: ClosedRange<CGFloat> = 0.88...1.06
    /// With Reduce Motion: a softer peak, and no swelling — the halo stays at
    /// its drawn size and only fades in and out.
    public static let reducedMotionPeakOpacity: Double = 0.6
    public static let reducedMotionScale: CGFloat = 1

    /// Where the pulse is (0 = dark, 1 = its peak) `time` seconds after it
    /// began: an eased rise to 1 at `pulseRise` (0.45 s), then a slower eased
    /// fall to 0 at `pulseDuration` (1.4 s). Each half is a half-cosine, so
    /// the curve leaves the dark, crests and lands without a corner. Before
    /// the pulse and after it: 0 — nothing is drawn.
    ///
    /// PROCEDURAL: NEO's core reports that it is listening, not how loud the
    /// room is, so the pulse has its own shape and claims nothing about the
    /// microphone's level.
    public static func pulse(at time: TimeInterval) -> Double {
        guard time > 0, time < pulseDuration else { return 0 }
        if time <= pulseRise {
            return 0.5 - 0.5 * cos(.pi * time / pulseRise)
        }
        return 0.5 + 0.5 * cos(.pi * (time - pulseRise) / pulseFall)
    }

    /// The halo's opacity at a point of the pulse.
    public static func glowOpacity(pulse: Double, reduceMotion: Bool = false) -> Double {
        (reduceMotion ? reducedMotionPeakOpacity : peakOpacity) * min(1, max(0, pulse))
    }

    /// The halo's scale at a point of the pulse.
    public static func glowScale(pulse: Double, reduceMotion: Bool = false) -> CGFloat {
        if reduceMotion { return reducedMotionScale }
        let p = CGFloat(min(1, max(0, pulse)))
        return pulseScaleRange.lowerBound + (pulseScaleRange.upperBound - pulseScaleRange.lowerBound) * p
    }

    /// The halo's square in the island's coordinates (top-left origin),
    /// centred on the pet. At the peak of the pulse it is drawn `scale` times
    /// this, about the same centre.
    public static func glowFrame(behind pet: PetLayout.Placement, scale: CGFloat = 1) -> CGRect {
        let side = glowDiameter(petSize: pet.size) * scale
        let inset = (pet.size - side) / 2
        return CGRect(x: pet.origin.x + inset, y: pet.origin.y + inset, width: side, height: side)
    }

    // MARK: - Where it shows

    /// Whether the glow shows in a shape: every shape the pet rides — the
    /// idle dock, the wings, the compact bar, the expanded island, and the
    /// notch strip of the dashboard, an app panel and a call's controls. Not
    /// where the pet steps aside.
    public static func shows(in state: IslandState) -> Bool {
        switch state {
        case .idle, .wings, .compact, .expanded, .interactive, .appPanel, .meeting:
            return true
        case .tray, .settings, .fileDrop, .skin,
             .teleprompter, .teleprompterCompose, .camera, .cameraExpanded, .neoPanel:
            return false
        }
    }
}
