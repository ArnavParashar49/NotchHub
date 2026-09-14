import CoreGraphics
import Testing
@testable import NotchHubCore

@Suite("IslandMotion")
struct IslandMotionTests {

    let notch = CGRect(x: 600, y: 24, width: 200, height: 32)
    let compact = CGRect(x: 560, y: 24, width: 356, height: 32)
    let expanded = CGRect(x: 406, y: 24, width: 587, height: 88)

    @Test("emerging from and draining into the notch")
    func peekAndRetract() {
        #expect(IslandMotion.between(from: notch, fromIdle: true, to: compact, toIdle: false) == .peek)
        #expect(IslandMotion.between(from: expanded, fromIdle: false, to: notch, toIdle: true) == .retract)
        #expect(IslandMotion.between(from: notch, fromIdle: true, to: notch, toIdle: true) == .none)
    }

    @Test("growing expands, shrinking collapses")
    func expandAndCollapse() {
        #expect(IslandMotion.between(from: compact, fromIdle: false, to: expanded, toIdle: false) == .expand)
        #expect(IslandMotion.between(from: expanded, fromIdle: false, to: compact, toIdle: false) == .collapse)
    }

    @Test("a small width change or a content swap is a morph")
    func morph() {
        let wider = CGRect(x: 550, y: 24, width: 380, height: 32)
        #expect(IslandMotion.between(from: compact, fromIdle: false, to: wider, toIdle: false) == .morph)
        #expect(IslandMotion.between(from: compact, fromIdle: false, to: compact, toIdle: false) == .morph)
    }

    @Test("shrinking springs are critically damped, and every motion has one")
    func springsPerMotion() {
        #expect(DesignTokens.animation(for: .none) == nil)
        for motion in [IslandMotion.peek, .expand, .collapse, .retract, .morph] {
            #expect(DesignTokens.animation(for: motion) != nil)
        }
    }
}
