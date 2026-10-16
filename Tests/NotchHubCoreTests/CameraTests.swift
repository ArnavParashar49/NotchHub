import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Camera")
struct CameraTests {

    private let built = CameraDevice(id: "built-in", name: "FaceTime HD Camera")
    private let external = CameraDevice(id: "usb-1", name: "Studio Display Camera")
    private let iphone = CameraDevice(id: "iphone", name: "Alex's iPhone")

    private func live(_ devices: [CameraDevice], on id: String) -> CameraState {
        CameraState(phase: .live, devices: devices, deviceID: id)
    }

    @Test("the camera is 'running' for exactly the phases that hold the device")
    func runningPhases() {
        // What "is the camera on?" is decided from — never the panel being open.
        #expect(CameraPhase.starting.isRunning)
        #expect(CameraPhase.live.isRunning)
        #expect(!CameraPhase.idle.isRunning)
        #expect(!CameraPhase.failed(.permissionDenied).isRunning)

        // A failure still holds the island, so its message can be read.
        #expect(!CameraPhase.idle.isPresented)
        for phase: CameraPhase in [.starting, .live, .failed(.noDevice)] {
            #expect(phase.isPresented)
        }
    }

    @Test("switching cycles through every camera and comes back round")
    func deviceCycle() {
        var state = live([built, external, iphone], on: built.id)
        #expect(state.canSwitchDevice)
        #expect(state.device == built)

        state.deviceID = state.nextDeviceID
        #expect(state.device == external)
        state.deviceID = state.nextDeviceID
        #expect(state.device == iphone)
        state.deviceID = state.nextDeviceID
        #expect(state.device == built, "the cycle did not wrap")
    }

    @Test("a single camera offers no switch, and an unknown one falls back to the first")
    func singleAndUnknownDevice() {
        let single = live([built], on: built.id)
        #expect(!single.canSwitchDevice)
        #expect(single.nextDeviceID == nil)
        #expect(!CameraLayout.controls(for: single).contains(.switchDevice))

        // The chosen camera was unplugged between sessions.
        let stale = live([built, external], on: "gone")
        #expect(stale.device == nil)
        #expect(stale.nextDeviceID == built.id)

        #expect(!CameraState().canSwitchDevice)
        #expect(CameraState().nextDeviceID == nil)
    }

    @Test("each phase offers only the controls that make sense for it")
    func controlsPerPhase() {
        // Live: resize, mirror, close — plus switching when there is a choice.
        #expect(CameraLayout.controls(for: live([built], on: built.id)) == [.toggleSize, .toggleMirror, .close])
        #expect(CameraLayout.controls(for: live([built, external], on: built.id))
                == [.toggleSize, .toggleMirror, .switchDevice, .close])

        // Starting: only a way out.
        #expect(CameraLayout.controls(for: CameraState(phase: .starting)) == [.close])

        // A refused camera offers the remedy; other failures cannot be fixed
        // from here, so they only offer a way out.
        #expect(CameraLayout.controls(for: CameraState(phase: .failed(.permissionDenied))) == [.openSettings, .close])
        #expect(CameraLayout.controls(for: CameraState(phase: .failed(.noDevice))) == [.close])
        #expect(CameraLayout.controls(for: CameraState(phase: .failed(.unavailable("busy")))) == [.close])
    }

    @Test("every control sits in the bar, clear of the picture, and hits itself")
    func controlLayout() {
        let frame = CGRect(x: 100, y: 700, width: 380, height: 246)
        let notchInset: CGFloat = 32
        let states = [
            live([built, external], on: built.id),
            live([built], on: built.id),
            CameraState(phase: .starting),
            CameraState(phase: .failed(.permissionDenied)),
            CameraState(phase: .failed(.noDevice)),
        ]

        for state in states {
            let placed = CameraLayout.actions(in: frame, state: state)
            #expect(Set(placed.map(\.action)) == Set(CameraLayout.controls(for: state)))
            let picture = CameraLayout.pictureFrame(in: frame, notchInset: notchInset)
            #expect(picture.maxY <= frame.maxY - notchInset, "the picture is behind the notch")
            #expect(picture.height > 0)

            for (index, item) in placed.enumerated() {
                #expect(frame.contains(item.rect), "\(item.action) outside the panel")
                #expect(!picture.intersects(item.rect), "\(item.action) is over the picture")
                let centre = CGPoint(x: item.rect.midX, y: item.rect.midY)
                #expect(CameraLayout.action(at: centre, in: frame, state: state) == item.action)
                for other in placed[(index + 1)...] {
                    #expect(!item.rect.intersects(other.rect), "\(item.action) overlaps \(other.action)")
                }
            }
            // Close always sits on its own at the trailing end.
            if let close = placed.first(where: { $0.action == .close }) {
                #expect(close.rect.maxX == frame.maxX - CameraLayout.horizontalInset)
            }
        }
    }

    @Test("both preview sizes are centred on the notch and keep a 16:9 picture")
    func previewFrames() {
        let g = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        )
        let small = g.cameraFrame(expanded: false)
        let large = g.cameraFrame(expanded: true)
        #expect(large.width > small.width)

        for frame in [small, large] {
            #expect(abs(frame.midX - g.notchFrame.midX) < 0.5)
            #expect(frame.maxY == g.notchFrame.maxY)
            #expect(g.envelopeFrame.contains(frame))
            // The picture is 16:9 within half a point, so the preview is never
            // letterboxed inside its own panel.
            let picture = CameraLayout.pictureFrame(in: frame, notchInset: g.notchFrame.height)
            #expect(abs(picture.width / picture.height - 16.0 / 9.0) < 0.02,
                    "picture is \(picture.width)x\(picture.height)")
        }
    }

    @Test("a refused camera says which fix to offer, and names a real settings pane")
    func failureCopy() {
        #expect(CameraFailure.permissionDenied.isPermission)
        #expect(!CameraFailure.noDevice.isPermission)
        #expect(!CameraFailure.unavailable("busy").isPermission)

        let denied = CameraState(phase: .failed(.permissionDenied))
        #expect(denied.statusText == "Camera access is off")
        #expect(denied.detailText == "Grant it in System Settings")

        let url = URL(string: CameraLayout.settingsURL)
        #expect(url?.scheme == "x-apple.systempreferences")

        // A live preview names the camera it is showing.
        #expect(live([built], on: built.id).statusText == built.name)
        #expect(live([built, external], on: built.id).detailText == "2 cameras")
    }
}
