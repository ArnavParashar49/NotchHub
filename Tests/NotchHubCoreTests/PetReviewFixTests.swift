import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Pet review fixes")
struct PetReviewFixTests {

    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test("Sleep from the panel holds through closing the panel and pointing at the pet")
    func sleepHolds() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.isHovering = true
        c.interactionOpen = true
        brain.update(c, now: at(1))
        brain.handle(.interaction(.sleep), context: c, now: at(2))
        c.interactionOpen = false
        brain.update(c, now: at(3))
        c.isPetHovered = true
        brain.update(c, now: at(4))
        brain.handle(.petHovered, context: c, now: at(4.1))
        #expect(brain.presentation.mood == .sleeping)
    }

    @Test("sleep is counted from the end of a long engagement")
    func sleepCountsFromEnd() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.inMeeting = true
        // A muted call schedules no updates: nothing runs until it ends.
        brain.update(c, now: at(0))
        c.inMeeting = false
        brain.update(c, now: at(1000.5))
        #expect(brain.presentation.mood == .idle)
    }

    @Test("charging does not keep the pet awake")
    func chargingSleeps() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.isCharging = true
        brain.update(c, now: at(0))
        brain.update(c, now: at(PetBrain.sleepAfter + 5))
        #expect(brain.presentation.mood == .sleeping)
    }

    @Test("with Idle Animations off, a resting and a sleeping pet are perfectly still")
    func idleOffIsStill() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.idleFlourishes = false
        let samples = stride(from: 0.0, through: 170, by: 0.5).map { brain.update(c, now: at($0)).animation }
        #expect(Set(samples) == [.sit])
        #expect(brain.update(c, now: at(400)).animation == .sleep)
        #expect(PetAnimationID.sleep.animation.isStatic)
        #expect(brain.nextWakeup(context: c, now: at(401)) == nil)
    }

    @Test("long activity poses are still; their motion is scheduled bursts")
    func stillActivityPoses() {
        #expect(PetAnimationID.codeType.animation.isStatic)
        #expect(PetAnimationID.download.animation.isStatic)
        #expect(!PetAnimationID.codeTypeBurst.animation.loops)
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.isAgentWorking = true
        brain.update(c, now: at(0))
        #expect(brain.presentation.mood == .coding)
        #expect(brain.nextWakeup(context: c, now: at(0)) != nil)
    }

    @Test("a repeated reaction restarts from its first frame")
    func repeatedReactionRestarts() {
        var brain = PetBrain(now: t0)
        let c = PetContext()
        brain.handle(.timerFinished, context: c, now: at(1))
        brain.handle(.timerFinished, context: c, now: at(1.3))
        #expect(brain.presentation.startedAt == at(1.3))
    }

    @Test("no flourish fires the instant a reaction ends")
    func noFlourishAfterReaction() {
        var brain = PetBrain(now: t0)
        let c = PetContext()
        brain.handle(.timerFinished, context: c, now: at(1))
        let end = 1 + PetAnimationID.timerDone.animation.duration
        #expect(brain.update(c, now: at(end + 0.1)).animation == .sit)
    }

    @Test("frames advance exactly on their boundaries despite floating point")
    func frameBoundaries() {
        let start = Date(timeIntervalSinceReferenceDate: 7.8e8)
        for duration in [0.14, 0.18, 0.3, 0.35, 0.8] {
            let animation = PetAnimation.loop(["a", "b", "c"], duration)
            for k in 0..<40 {
                let tick = start.addingTimeInterval(Double(k) * duration)
                #expect(animation.frameIndex(at: tick.timeIntervalSince(start)) == k % 3)
            }
        }
    }

    @Test("hover-strip browser buttons honour the pet reserve without shifting")
    func wingButtonsWithReserve() {
        let side: CGFloat = 132
        let frame = CGRect(x: 500, y: 0, width: 185 + side * 2, height: 32)
        let buttons = WingControlLayout.browserButtons(in: frame, notchWidth: 185, inset: 16, trailingReserve: PetLayout.barSlot)
        #expect(buttons[0].rect.minX == frame.maxX - 16 - PetLayout.barSlot - WingControlLayout.controlsWidth)
        #expect(buttons.last!.rect.maxX <= frame.maxX - 16 - PetLayout.barSlot)
    }

    @Test("the pet panel hangs from the pet's edge and stays joined to the notch")
    func anchoredPanel() {
        let g = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        )
        #expect(g.petPanelFrame(anchor: nil) == g.skinFrame)
        for edge in [g.notchFrame.maxX + PetLayout.idleDock, g.notchFrame.maxX + 250] {
            let panel = g.petPanelFrame(anchor: PetPanelAnchor(edge: edge, side: .right))
            #expect(panel.maxX == edge)
            #expect(panel.minX <= g.notchFrame.minX)
            #expect(panel.width >= g.skinFrame.width)
            #expect(g.envelopeFrame.contains(panel))
        }
        let left = g.petPanelFrame(anchor: PetPanelAnchor(edge: g.notchFrame.minX - PetLayout.idleDock, side: .left))
        #expect(left.minX <= g.notchFrame.minX - PetLayout.idleDock)
        #expect(left.minX + PetPanelLayout.horizontalInset + PetPanelLayout.petSize <= g.notchFrame.minX)
        #expect(left.maxX >= g.notchFrame.maxX)
        #expect(left.width >= g.skinFrame.width)
        #expect(g.envelopeFrame.contains(left))
    }
}
