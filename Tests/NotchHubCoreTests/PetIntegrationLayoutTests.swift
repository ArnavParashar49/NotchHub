import AppKit
import CoreGraphics
import Testing
@testable import NotchHubCore

@Suite("Pet integration layout")
struct PetIntegrationLayoutTests {

    /// The 14-inch MacBook Pro geometry this app runs on: a 185 pt notch at a
    /// fractional x (663.5).
    func geometry() -> NotchGeometry {
        NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        )
    }

    @Test("without the pet, idle is exactly the notch")
    func idleWithoutPet() {
        let g = geometry()
        #expect(g.frame(for: .idle, content: .default) == g.notchFrame)
    }

    @Test("with the pet, idle reaches right of the notch by the dock, flush with the notch's left edge")
    func idleDock() {
        let g = geometry()
        var content = IslandContentSize.default
        content.petDock = .home
        let idle = g.frame(for: .idle, content: content)
        #expect(idle.minX == g.notchFrame.minX)
        #expect(idle.maxY == g.notchFrame.maxY)
        #expect(idle.height == g.notchFrame.height)
        #expect(idle.width == g.notchFrame.width + PetLayout.idleDock)
        #expect(g.envelopeFrame.contains(idle))

        // The pet sits wholly right of the physical notch, where there are pixels.
        let pet = PetLayout.placement(for: .idle, islandSize: idle.size, notchHeight: 32)!
        #expect(idle.minX + pet.origin.x >= g.notchFrame.maxX)
    }

    @Test("the transport cluster steps aside by exactly the reserve")
    func transportReserve() {
        let island = CGRect(x: 400, y: 0, width: 587, height: 88)
        let plain = MediaControlLayout.placement(in: island, notchInset: 32)
        let reserved = MediaControlLayout.placement(in: island, notchInset: 32, trailingReserve: PetLayout.expandedReserve)
        #expect(plain.cluster.minX - reserved.cluster.minX == PetLayout.expandedReserve)
        #expect(plain.cluster.minY == reserved.cluster.minY)
        // …and the 2x pet fits in that reserve without touching the cluster.
        let pet = PetLayout.placement(for: .expanded, islandSize: island.size, notchHeight: 32)!
        #expect(island.minX + pet.origin.x >= reserved.cluster.maxX)
    }

    @Test("the pet panel's action chips fit the panel, below the notch, without overlapping the pet")
    func petPanel() {
        let g = geometry()
        let frame = g.frame(for: .skin, content: .default)
        let chips = PetPanelLayout.actions(in: frame, notchInset: 32)
        #expect(chips.map(\.action) == PetInteraction.allCases)
        let petRight = frame.minX + PetPanelLayout.horizontalInset + PetLayout.artSize * PetPanelLayout.petScale
        for (i, chip) in chips.enumerated() {
            #expect(frame.contains(chip.rect))
            #expect(chip.rect.maxY <= frame.maxY - 32)
            #expect(chip.rect.minX > petRight)
            let centre = CGPoint(x: chip.rect.midX, y: chip.rect.midY)
            #expect(PetPanelLayout.action(at: centre, in: frame, notchInset: 32) == chip.action)
            for other in chips[(i + 1)...] {
                #expect(!chip.rect.intersects(other.rect))
            }
        }
    }
}
