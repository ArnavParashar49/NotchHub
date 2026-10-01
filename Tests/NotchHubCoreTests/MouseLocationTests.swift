import CoreGraphics
import Testing
@testable import NotchHubCore

@Suite("Mouse location")
struct MouseLocationTests {

    let island = CGRect(x: 300, y: 700, width: 1100, height: 400)

    @Test("an event in the island's own window is already local")
    func ownWindow() {
        let point = CGPoint(x: 400, y: 380)
        #expect(MouseLocation.inWindow(point, eventWindowFrame: island, windowFrame: island) == point)
    }

    @Test("an event with no window is in screen coordinates: a far-away cursor stays far away")
    func noWindow() {
        // The cursor at screen (390, 1080) — over the island's notch — reads
        // as (90, 380) in the window, not as the screen point itself.
        #expect(MouseLocation.inWindow(CGPoint(x: 390, y: 1080), eventWindowFrame: nil, windowFrame: island) == CGPoint(x: 90, y: 380))
        // The cursor at screen (390, 380) — far below the island — would, taken
        // as window-local, have landed on the notch strip. It lands outside.
        let far = MouseLocation.inWindow(CGPoint(x: 390, y: 380), eventWindowFrame: nil, windowFrame: island)
        #expect(far == CGPoint(x: 90, y: -320))
        #expect(!CGRect(origin: .zero, size: island.size).contains(far))
    }

    @Test("an event in another window is carried through that window to the screen")
    func otherWindow() {
        let other = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(MouseLocation.inWindow(CGPoint(x: 290, y: 980), eventWindowFrame: other, windowFrame: island) == CGPoint(x: 90, y: 380))
    }
}
