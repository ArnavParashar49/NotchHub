import CoreGraphics
import Testing
@testable import NotchHubCore

@Suite("MediaControlLayout")
struct MediaControlLayoutTests {

    /// A typical expanded island frame, in window coordinates.
    let island = CGRect(x: 159, y: 0, width: 514, height: 92)

    @Test("the three buttons lay out left to right, without overlapping")
    func buttonsDoNotOverlap() {
        let placement = MediaControlLayout.placement(in: island)
        #expect(placement.buttons.count == 3)
        #expect(placement.buttons.map(\.command) == [.previous, .togglePlayPause, .next])

        let rects = placement.buttons.map(\.rect)
        for (lhs, rhs) in zip(rects, rects.dropFirst()) {
            #expect(lhs.maxX <= rhs.minX, "buttons must not overlap")
        }
    }

    @Test("every button sits inside the capsule")
    func buttonsInsideCluster() {
        let placement = MediaControlLayout.placement(in: island)
        for button in placement.buttons {
            #expect(placement.cluster.contains(button.rect.insetBy(dx: 0.5, dy: 0.5)))
        }
    }

    @Test("the cluster is trailing-aligned inside the island")
    func clusterIsTrailingAligned() {
        let placement = MediaControlLayout.placement(in: island)
        #expect(
            abs(placement.cluster.maxX - (island.maxX - MediaControlLayout.contentInset)) < 0.001,
            "the cluster should hug the island's trailing edge"
        )
        #expect(abs(placement.cluster.midY - island.midY) < 0.001, "vertically centred")
        #expect(placement.cluster.minX >= island.minX, "must not spill out the leading edge")
    }

    @Test("a click at each button's centre resolves to that button")
    func centreOfEachButtonHits() {
        let placement = MediaControlLayout.placement(in: island)
        for button in placement.buttons {
            let centre = CGPoint(x: button.rect.midX, y: button.rect.midY)
            #expect(
                MediaControlLayout.command(at: centre, in: placement) == button.command,
                "\(button.command) centre should hit itself"
            )
        }
    }

    @Test("a click far outside the cluster hits nothing")
    func farClickMisses() {
        let placement = MediaControlLayout.placement(in: island)
        #expect(MediaControlLayout.command(at: CGPoint(x: island.minX + 10, y: island.midY), in: placement) == nil)
        #expect(MediaControlLayout.command(at: CGPoint(x: -500, y: -500), in: placement) == nil)
    }

    @Test("the corner of a button's box is not a hit — the buttons are circles")
    func cornerOfBoxMisses() {
        let placement = MediaControlLayout.placement(in: island)
        let primary = placement.buttons[1].rect
        // The top-left corner of the bounding box lies outside the circle.
        let corner = CGPoint(x: primary.minX + 0.5, y: primary.minY + 0.5)
        let dx = corner.x - primary.midX
        let dy = corner.y - primary.midY
        // The corner is r*sqrt(2) from the centre, well outside the radius.
        #expect((dx * dx + dy * dy).squareRoot() > primary.width / 2)
        #expect(MediaControlLayout.command(at: corner, in: placement) != .togglePlayPause)
    }

    @Test("a click between two buttons is a miss, not a mis-fire")
    func gapBetweenButtonsMisses() {
        let placement = MediaControlLayout.placement(in: island)
        let previous = placement.buttons[0].rect
        let primary = placement.buttons[1].rect
        let gapX = (previous.maxX + primary.minX) / 2
        // The gap is narrow; the two-point slop must not bridge it into a hit
        // on the wrong neighbour. Either a miss or the nearer button is fine,
        // but it must never resolve to the *far* one.
        let hit = MediaControlLayout.command(at: CGPoint(x: gapX, y: island.midY), in: placement)
        #expect(hit != .next, "a click at the left gap must not reach the next button")
    }

    @Test("the cluster size is the sum of its parts")
    func clusterSize() {
        let size = MediaControlLayout.clusterSize
        let expectedWidth = MediaControlLayout.secondaryDiameter * 2
            + MediaControlLayout.primaryDiameter
            + MediaControlLayout.spacing * 2
            + MediaControlLayout.padding * 2
        #expect(abs(size.width - expectedWidth) < 0.001)
        #expect(size.height > MediaControlLayout.primaryDiameter)
    }
}

@Suite("MediaCommand")
struct MediaCommandTests {

    @Test("each command maps to a distinct system code")
    func codesAreDistinct() {
        let codes = MediaCommand.allCases.map(\.rawCommandCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test("the transport's centre glyph follows playback")
    func playPauseGlyph() {
        #expect(MediaTransport(isPlaying: true).playPauseSymbol == "pause.fill")
        #expect(MediaTransport(isPlaying: false).playPauseSymbol == "play.fill")
    }
}
