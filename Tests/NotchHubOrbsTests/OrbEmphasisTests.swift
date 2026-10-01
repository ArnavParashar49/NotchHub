import Foundation
import Testing
@testable import NotchHubOrbs

@Suite("Orb emphasis")
struct OrbEmphasisTests {

    @Test("the notch emphasis keeps the geometry and lifts only the paint")
    func liftsPaint() {
        let preset = OrbEngine.resolvePreset(state: .searching, size: .large)
        let frame = OrbEngine.frame(mode: preset.mode, size: 28, t: 1.3, opts: preset.opts)
        let lifted = OrbEmphasis.notch.apply(to: frame, dark: true)
        #expect(lifted.dots.count == frame.dots.count)
        #expect(lifted.lines.count == frame.lines.count)
        for (a, b) in zip(frame.dots, lifted.dots) {
            #expect(a.x == b.x && a.y == b.y && a.z == b.z)
            #expect(b.r >= 0.85 && b.r >= a.r)
            #expect(b.a >= a.a && b.a <= 1)
            let level = OrbView.inkLevel(b.white, dark: true)
            #expect(level >= 0.42 - 1e-9 && level <= 0.95 + 1e-9)
        }
        // The nearest dots read as white (~0.95): the orb is unmistakable on black.
        let brightest = lifted.dots.map { OrbView.inkLevel($0.white, dark: true) }.max() ?? 0
        #expect(brightest > 0.9)
        // The 64-pt design at 28 pt still has its dots — not the sparse small preset's few.
        let small = OrbEngine.resolvePreset(state: .searching, size: .small)
        let sparse = OrbEngine.frame(mode: small.mode, size: 28, t: 1.3, opts: small.opts)
        #expect(frame.dots.count > sparse.dots.count * 2)
    }

    @Test("without an emphasis the painter's input is the engine's own frame")
    func identityWithoutEmphasis() {
        let preset = OrbEngine.resolvePreset(state: .connecting, size: .large)
        let frame = OrbEngine.frame(mode: preset.mode, size: 64, t: 0.5, opts: preset.opts)
        let unit = OrbEmphasis(dotScale: 1, dotFloor: 0, lineScale: 1, inkPeak: 1, inkFloor: 0, alphaGain: 1)
        // The ink round-trips through the painter's 8-bit grey, so to within one level.
        let same = unit.apply(to: frame, dark: true)
        for (a, b) in zip(frame.dots, same.dots) {
            #expect(abs(a.r - b.r) < 1e-12 && abs(a.white - b.white) <= 1.0 / 255 && abs(a.a - b.a) < 1e-12)
        }
    }
}
