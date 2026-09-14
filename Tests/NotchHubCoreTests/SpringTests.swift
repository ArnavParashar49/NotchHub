import Testing
@testable import NotchHubCore

@Suite("Spring")
struct SpringTests {

    @Test("a spring starts at its origin")
    func startsAtOrigin() {
        #expect(abs(Spring.expand.value(from: 0, to: 100, at: 0)) < 1e-9)
    }

    @Test("every preset converges to its target")
    func convergesToTarget() {
        for spring in [Spring.expand, Spring.settle, Spring.contract] {
            let v = spring.value(from: 0, to: 100, at: 3.0)
            #expect(abs(v - 100) < 0.5)
        }
    }

    @Test("no NaN across a sweep")
    func noNaN() {
        let s = Spring.expand
        for i in 0...600 {
            #expect(!s.value(from: -50, to: 150, at: Double(i) / 240).isNaN)
        }
    }

    @Test("expand overshoots only slightly")
    func expandOvershootsSlightly() {
        let s = Spring.expand
        let peak = (0...480).map { s.value(from: 0, to: 100, at: Double($0) / 240) }.max() ?? 0
        #expect(peak > 100)
        #expect(peak < 112)
    }

    @Test("contract settles faster than expand")
    func contractIsFast() {
        let expand = Spring.expand.settlingDuration(from: 0, to: 100)
        let contract = Spring.contract.settlingDuration(from: 0, to: 100)
        #expect(contract < expand)
    }

    @Test("the animator steps and settles")
    func animatorStepsAndSettles() {
        var a = SpringAnimator(from: 0, to: 100, spring: .expand)
        for _ in 0..<600 { a.step(1.0 / 240) }
        #expect(a.isSettled)
        #expect(abs(a.value - 100) < 1.0)
    }

    @Test("retargeting carries position — no snap")
    func retargetDoesNotSnap() {
        var a = SpringAnimator(from: 0, to: 100, spring: .expand)
        for _ in 0..<30 { a.step(1.0 / 240) }
        let before = a.value
        a.retarget(to: 60, spring: .settle)
        #expect(abs(a.value - before) < 0.5)
    }

    @Test("damping ratios classify the presets")
    func zetaClassification() {
        // All presets are underdamped — the island always carries a whisper of
        // overshoot so it feels alive, never dead-on-arrival.
        #expect(Spring.expand.zeta < 1)
        #expect(Spring.settle.zeta < 1)
        #expect(Spring.contract.zeta < 1)
    }
}
