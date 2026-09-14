import CoreGraphics
import Foundation

/// A damped spring, solved analytically.
///
/// The island's motion is one continuous physical object, so every transition
/// is driven by a spring rather than an easing curve. Presets are tuned to
/// Apple's feel: fast on appear, smooth on settle, almost imperceptible on
/// disappear, with only a whisper of overshoot.
public struct Spring: Equatable {
    public var stiffness: Double
    public var damping: Double
    public var mass: Double
    /// Initial velocity, in units per second.
    public var initialVelocity: Double

    public init(stiffness: Double, damping: Double, mass: Double = 1, initialVelocity: Double = 0) {
        self.stiffness = stiffness
        self.damping = damping
        self.mass = mass
        self.initialVelocity = initialVelocity
    }

    /// Natural frequency.
    public var omega0: Double { (stiffness / mass).squareRoot() }
    /// Damping ratio: < 1 underdamped (overshoots), 1 critical, > 1 overdamped.
    public var zeta: Double { damping / (2 * (stiffness * mass).squareRoot()) }

    /// Value at time `t`, travelling from `from` to `to`.
    ///
    /// Handles under-, critically-, and over-damped regimes.
    public func value(from: Double, to: Double, at t: Double) -> Double {
        guard t > 0 else { return from }
        let delta = to - from
        let w0 = omega0
        let z = zeta

        if abs(z - 1) < 1e-6 {
            // Critically damped.
            let c2 = initialVelocity + w0 * delta
            return to - (delta + c2 * t) * exp(-w0 * t)
        }

        if z < 1 {
            // Underdamped — the regime that gives the island its life.
            let wd = w0 * (1 - z * z).squareRoot()
            let a = delta
            let b = (initialVelocity + z * w0 * delta) / wd
            return to - exp(-z * w0 * t) * (a * cos(wd * t) + b * sin(wd * t))
        }

        // Overdamped.
        let s = w0 * (z * z - 1).squareRoot()
        let r1 = -z * w0 + s
        let r2 = -z * w0 - s
        let c2 = (initialVelocity - r1 * delta) / (r2 - r1)
        let c1 = delta - c2
        return to - (c1 * exp(r1 * t) + c2 * exp(r2 * t))
    }

    /// Time at which the spring is considered settled (within `tolerance`).
    public func settlingDuration(from: Double, to: Double, tolerance: Double = 0.001) -> Double {
        let delta = abs(to - from)
        guard delta > tolerance else { return 0 }
        var t = 0.0
        let step = 1.0 / 240.0
        while t < 10 {
            if abs(value(from: from, to: to, at: t) - to) < tolerance { return t }
            t += step
        }
        return t
    }
}

// MARK: - Presets

public extension Spring {
    /// Appearing: quick, confident, a whisper of overshoot.
    static let expand = Spring(stiffness: 320, damping: 26, mass: 1, initialVelocity: 0)
    /// Settling: smooth, barely any overshoot.
    static let settle = Spring(stiffness: 260, damping: 30, mass: 1, initialVelocity: 0)
    /// Disappearing: fast and almost imperceptible.
    static let contract = Spring(stiffness: 420, damping: 34, mass: 1, initialVelocity: 0)
    /// Content crossfades ride a slightly softer spring than the geometry.
    static let content = Spring(stiffness: 280, damping: 28, mass: 1, initialVelocity: 0)
}

/// Steps a single value toward a target over time using a `Spring`.
///
/// The animator is pure state — the view layer drives it from a display link
/// or a SwiftUI timeline, which keeps the physics testable.
public struct SpringAnimator {
    public private(set) var from: Double
    public private(set) var to: Double
    public private(set) var spring: Spring
    public private(set) var elapsed: Double = 0
    public private(set) var isSettled: Bool = false

    public init(from: Double, to: Double, spring: Spring) {
        self.from = from
        self.to = to
        self.spring = spring
    }

    public var value: Double {
        spring.value(from: from, to: to, at: elapsed)
    }

    /// Advances the animator by `dt` seconds.
    public mutating func step(_ dt: Double, tolerance: Double = 0.001) {
        guard !isSettled else { return }
        elapsed += dt
        if abs(value - to) < tolerance, abs(velocity) < tolerance * 10 {
            isSettled = true
        }
    }

    /// Retargets the animator, carrying current position and velocity forward
    /// so an interrupted transition never snaps.
    public mutating func retarget(to newTarget: Double, spring newSpring: Spring) {
        let currentValue = value
        let currentVelocity = velocity
        from = currentValue
        to = newTarget
        spring = Spring(
            stiffness: newSpring.stiffness,
            damping: newSpring.damping,
            mass: newSpring.mass,
            initialVelocity: currentVelocity
        )
        elapsed = 0
        isSettled = false
    }

    /// Instantaneous velocity, by central difference.
    public var velocity: Double {
        let h = 1.0 / 1000.0
        let a = spring.value(from: from, to: to, at: max(0, elapsed - h))
        let b = spring.value(from: from, to: to, at: elapsed + h)
        return (b - a) / (2 * h)
    }
}
