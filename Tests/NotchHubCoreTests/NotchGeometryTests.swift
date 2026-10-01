import AppKit
import Testing
@testable import NotchHubCore

/// A 1728×1117 display with a 200pt notch and 38pt safe-area top inset.
private func makeGeometry() -> NotchGeometry {
    NotchGeometry.make(
        screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0)
    )
}

@Suite("NotchGeometry")
struct NotchGeometryTests {

    @Test("notch is centered at the top of the screen")
    func notchCenteredAtTop() {
        let g = makeGeometry()
        #expect(g.hasNotch)
        #expect(abs(g.notchFrame.midX - 1728 / 2) < 0.001)
        #expect(abs(g.notchFrame.maxY - 1117) < 0.001)
        #expect(abs(g.notchFrame.height - 38) < 0.001)
        #expect(abs(g.notchFrame.width - 200) < 0.001)
    }

    @Test("compact bar grows sideways at notch height, never downward")
    func compactBarGrowsSideways() {
        let g = makeGeometry()
        // Wider than the notch, but exactly notch-height — it must not hang
        // below the cutout.
        #expect(g.compactFrame.width > g.notchFrame.width)
        #expect(abs(g.compactFrame.height - g.notchFrame.height) < 0.001)
        #expect(abs(g.compactFrame.maxY - g.notchFrame.maxY) < 0.001)
        // The compact bar is asymmetric: a snug left wing, a wider right wing.
        #expect(abs(g.compactFrame.minX - (g.notchFrame.minX - NotchGeometry.compactLeadOverhang)) < 0.001)
        #expect(abs(g.compactFrame.maxX - (g.notchFrame.maxX + NotchGeometry.compactTrailOverhang)) < 0.001)
        // The notch region inside it must still centre on the real notch,
        // or content would land under the physical cutout.
        #expect(abs(g.compactFrame.minX + NotchGeometry.compactLeadOverhang - g.notchFrame.minX) < 0.001)
    }

    @Test("expanded island is wider, centered, and capped")
    func expandedIsWiderAndCentered() {
        let g = makeGeometry()
        #expect(abs(g.expandedFrame.midX - g.notchFrame.midX) < 0.001)
        #expect(g.expandedFrame.width > g.compactFrame.width)
        #expect(g.expandedFrame.width <= 620)
        #expect(abs(g.expandedFrame.maxY - g.notchFrame.maxY) < 0.001)
    }

    @Test("a display without a notch still yields sane geometry")
    func noNotchDetection() {
        let g = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        )
        #expect(!g.hasNotch)
        #expect(abs(g.notchFrame.width - NotchGeometry.fallbackNotchWidth) < 0.001)
    }

    @Test("the gap between auxiliary menu-bar areas defines the notch")
    func auxiliaryGapDefinesNotch() {
        let left = CGRect(x: 0, y: 1079, width: 800, height: 38)
        let right = CGRect(x: 950, y: 1079, width: 778, height: 38)
        let g = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: left,
            auxiliaryRight: right
        )
        #expect(abs(g.notchFrame.width - 150) < 0.001)
        #expect(abs(g.notchFrame.midX - 1728 / 2) < 0.001)
    }

    @Test("frame(for:) maps each state to its shape")
    func frameForState() {
        let g = makeGeometry()
        #expect(g.frame(for: .idle) == g.notchFrame)
        #expect(g.frame(for: .wings) == g.wingsFrame)
        #expect(g.frame(for: .compact) == g.compactFrame)
        #expect(g.frame(for: .expanded) == g.expandedFrame)
        #expect(g.frame(for: .interactive) == g.interactiveFrame)
        #expect(g.frame(for: .tray) == g.trayFrame)
        #expect(g.frame(for: .teleprompter) == g.teleprompterFrame)
        // The Tray opens as the hover strip, growing down out of it, so the two
        // share an outline rather than stepping to some unrelated width. It is
        // matched to the strip CARRYING CONTENT, which is the one on screen
        // nearly every time — so it is never narrower than the bare strip.
        #expect(g.trayFrame.width == g.wingsBar(sideWidth: NotchGeometry.wingContentWidth).width)
        #expect(g.trayFrame.width >= g.wingsFrame.width)
        #expect(g.envelopeFrame.contains(g.trayFrame))
        #expect(g.frame(for: .meeting) == g.meetingFrame)
        #expect(g.frame(for: .skin) == g.skinFrame)
        #expect(g.frame(for: .settings) == g.settingsFrame)
    }

    @Test("wings are notch-height and stretch sideways, never downward")
    func wingsAreSideways() {
        let g = makeGeometry()
        // Same height as the notch — the bar hugs the top edge.
        #expect(abs(g.wingsFrame.height - g.notchFrame.height) < 0.001)
        // Wider than the notch.
        #expect(g.wingsFrame.width > g.notchFrame.width)
        // Top edge flush with the screen — it never grows downward.
        #expect(abs(g.wingsFrame.maxY - g.notchFrame.maxY) < 0.001)
        // SYMMETRIC: equal wings, so the island grows evenly about the notch.
        #expect(abs(g.wingsFrame.minX - (g.notchFrame.minX - NotchGeometry.wingWidth)) < 0.001)
        #expect(abs(g.wingsFrame.maxX - (g.notchFrame.maxX + NotchGeometry.wingWidth)) < 0.001)
        // The notch is the centre of the expanded bar.
        #expect(abs(g.wingsFrame.midX - g.notchFrame.midX) < 0.001)
    }

    @Test("the envelope contains the wings")
    func envelopeContainsWings() {
        let g = makeGeometry()
        #expect(g.envelopeFrame.contains(g.wingsFrame))
    }

    @Test("settings panel is a tall, centered surface hung from the top")
    func settingsPanelGeometry() {
        let g = makeGeometry()
        #expect(abs(g.settingsFrame.midX - g.notchFrame.midX) < 0.001)
        #expect(abs(g.settingsFrame.maxY - g.notchFrame.maxY) < 0.001)
        #expect(g.settingsFrame.height > g.trayFrame.height)
        #expect(g.settingsFrame.width <= 460)
        #expect(g.settingsFrame.width <= g.screenFrame.width)
    }

    @Test("content-driven sizing expands the wings and compact bar to fit content")
    func contentDrivenSizing() {
        let g = makeGeometry()
        let largeContent = IslandContentSize(compactLead: 80, compactTrail: 200, wingSide: 160)
        let wings = g.frame(for: .wings, content: largeContent)
        let compact = g.frame(for: .compact, content: largeContent)

        // Wings: expanded symmetrically around the notch
        #expect(abs(wings.width - (g.notchFrame.width + 160 * 2)) < 0.001)
        #expect(abs(wings.midX - g.notchFrame.midX) < 0.001)

        // Compact: lead on left, trail on right, notch region aligned
        #expect(abs(compact.width - (g.notchFrame.width + 80 + 200)) < 0.001)
        #expect(abs(compact.minX - (g.notchFrame.minX - 80)) < 0.001)

        // Envelope contains the enlarged content frames
        #expect(g.envelopeFrame.contains(wings))
        #expect(g.envelopeFrame.contains(compact))
    }

    @Test("the envelope contains every surface, including settings")
    func envelopeContainsSettings() {
        let g = makeGeometry()
        #expect(g.envelopeFrame.contains(g.settingsFrame))
        #expect(g.envelopeFrame.contains(g.trayFrame))
        #expect(g.envelopeFrame.contains(g.notchFrame))
    }

    @Test("the click dashboard is taller than expanded and centred under the notch")
    func interactiveIsTaller() {
        let g = makeGeometry()
        #expect(g.interactiveFrame.width <= NotchGeometry.interactiveMaxWidth)
        #expect(g.interactiveFrame.width > g.notchFrame.width)
        #expect(g.interactiveFrame.height > g.expandedFrame.height)
        #expect(abs(g.interactiveFrame.midX - g.notchFrame.midX) < 0.001)
        #expect(abs(g.interactiveFrame.maxY - g.notchFrame.maxY) < 0.001)
    }
}
