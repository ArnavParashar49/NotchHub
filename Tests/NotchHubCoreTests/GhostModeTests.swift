import Foundation
import Testing
@testable import NotchHubCore

@Suite("Ghost Mode")
struct GhostModeTests {

    /// Every shape the island can take that is NOT private by nature.
    private var ordinaryStates: [IslandState] {
        IslandState.allCases.filter { !GhostMode.alwaysPrivate.contains($0) }
    }

    @Test("with Ghost Mode off, ordinary surfaces are captured as usual")
    func offByDefault() {
        for state in ordinaryStates {
            #expect(!GhostMode.hidesFromCapture(state: state, ghostModeEnabled: false),
                    "\(state) was hidden with Ghost Mode off")
            #expect(GhostMode.reason(state: state, ghostModeEnabled: false) == nil)
        }
    }

    @Test("with Ghost Mode on, every surface is hidden")
    func hidesEverything() {
        for state in IslandState.allCases {
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: true),
                    "\(state) was still capturable with Ghost Mode on")
        }
    }

    @Test("the teleprompter and the camera are hidden whether or not Ghost Mode is on")
    func alwaysPrivateSurfaces() {
        // The whole point: a script the room can read is not a teleprompter,
        // a self-view inside the screen you are sharing is never what you
        // meant, and nobody should have to remember to arm anything first.
        for state: IslandState in [.teleprompter, .teleprompterCompose, .camera, .cameraExpanded] {
            #expect(GhostMode.alwaysPrivate.contains(state))
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: false),
                    "\(state) would have been screen-shared")
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: true))
            // And it says WHY, so the setting's state is never blamed for it.
            #expect(GhostMode.reason(state: state, ghostModeEnabled: false) == .alwaysPrivateSurface)
            #expect(GhostMode.reason(state: state, ghostModeEnabled: true) == .alwaysPrivateSurface)
        }
    }

    @Test("an ordinary surface hidden by the setting says the setting is why")
    func reasonIsTheSetting() {
        #expect(GhostMode.reason(state: .compact, ghostModeEnabled: true) == .ghostMode)
        #expect(GhostMode.reason(state: .interactive, ghostModeEnabled: true) == .ghostMode)
    }

    @Test("ordinary surfaces still follow the setting")
    func ordinarySurfacesFollowTheSetting() {
        // Only the surfaces whose CONTENT gives something away are unconditional.
        // Everything else — a song, the dashboard, the Tray — is the user's call.
        for state: IslandState in [.compact, .expanded, .interactive, .tray, .wings] {
            #expect(!GhostMode.alwaysPrivate.contains(state))
            #expect(!GhostMode.hidesFromCapture(state: state, ghostModeEnabled: false))
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: true))
        }
    }
}
