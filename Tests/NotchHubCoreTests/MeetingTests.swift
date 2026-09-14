import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Meeting")
struct MeetingTests {

    // MARK: Shortcuts

    @Test("shortcuts use virtual key codes, not ASCII values")
    func shortcutsAreVirtualKeyCodes() {
        let zoomMute = MeetingApp.zoom.shortcut(for: .mute)
        #expect(zoomMute == KeyChord(keyCode: 0x00, command: true, shift: true)) // ⌘⇧A
        #expect(zoomMute?.keyCode != 97) // "a" as ASCII is F6
        #expect(MeetingApp.zoom.shortcut(for: .camera)?.keyCode == 0x09) // V
        #expect(MeetingApp.zoom.shortcut(for: .leave) == KeyChord(keyCode: 0x0D)) // ⌘W
    }

    @Test("Teams and Meet use their own shortcuts")
    func perAppShortcuts() {
        #expect(MeetingApp.teams.shortcut(for: .mute) == KeyChord(keyCode: 0x2E, shift: true)) // ⌘⇧M
        #expect(MeetingApp.teams.shortcut(for: .camera) == KeyChord(keyCode: 0x1F, shift: true)) // ⌘⇧O
        #expect(MeetingApp.teams.shortcut(for: .leave) == KeyChord(keyCode: 0x04, shift: true)) // ⌘⇧H
        #expect(MeetingApp.googleMeet.shortcut(for: .mute) == KeyChord(keyCode: 0x02)) // ⌘D
        #expect(MeetingApp.googleMeet.shortcut(for: .leave) == nil)
    }

    // MARK: Detection

    @Test("an open call app with no call is not a meeting")
    func openAppIsNotACall() {
        let app = MeetingDetector.detect(
            runningBundleIDs: ["us.zoom.xos", "com.microsoft.teams2"],
            processNames: ["zoom.us", "MSTeams"],
            inputBundleIDs: [],
            microphoneInUse: false
        )
        #expect(app == nil)
    }

    @Test("Zoom's in-meeting helper process signals a call")
    func zoomHelperSignalsCall() {
        for helper in ["CptHost", "aomhost"] {
            let app = MeetingDetector.detect(
                runningBundleIDs: ["us.zoom.xos"],
                processNames: ["zoom.us", helper],
                inputBundleIDs: [],
                microphoneInUse: false
            )
            #expect(app == .zoom)
        }
    }

    @Test("the call app capturing the microphone signals a call, helpers included")
    func microphoneCaptureSignalsCall() {
        #expect(MeetingDetector.detect(
            runningBundleIDs: ["com.microsoft.teams2"],
            processNames: [],
            inputBundleIDs: ["com.microsoft.teams2"],
            microphoneInUse: true
        ) == .teams)
        #expect(MeetingDetector.detect(
            runningBundleIDs: ["com.microsoft.teams2"],
            processNames: [],
            inputBundleIDs: ["com.microsoft.teams2.helper"],
            microphoneInUse: true
        ) == .teams)
    }

    @Test("another app using the microphone is not the call app's call")
    func otherAppMicrophoneIsNotACall() {
        let app = MeetingDetector.detect(
            runningBundleIDs: ["com.microsoft.teams2"],
            processNames: [],
            inputBundleIDs: ["com.apple.VoiceMemos"],
            microphoneInUse: true
        )
        #expect(app == nil)
    }

    @Test("without per-process audio info, the device-wide mic flag is the fallback")
    func legacyMicrophoneFallback() {
        #expect(MeetingDetector.detect(
            runningBundleIDs: ["com.microsoft.teams2"],
            processNames: [],
            inputBundleIDs: nil,
            microphoneInUse: true
        ) == .teams)
    }

    @Test("a helper process without its app running is not a call")
    func helperWithoutApp() {
        #expect(MeetingDetector.detect(
            runningBundleIDs: [],
            processNames: ["CptHost"],
            inputBundleIDs: nil,
            microphoneInUse: true
        ) == nil)
    }

    // MARK: Control layout

    @Test("each control button resolves to its control; the header does not")
    func controlLayoutHitTest() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 132)
        let inset: CGFloat = 32
        let buttons = MeetingControlLayout.buttons(in: frame, notchInset: inset)
        #expect(buttons.map(\.control) == [.mute, .camera, .leave])
        for button in buttons {
            let centre = CGPoint(x: button.rect.midX, y: button.rect.midY)
            #expect(MeetingControlLayout.control(at: centre, in: frame, notchInset: inset) == button.control)
            // Every button sits inside the panel, below the notch.
            #expect(frame.contains(button.rect))
            #expect(button.rect.maxY <= frame.maxY - inset)
        }
        #expect(MeetingControlLayout.control(at: CGPoint(x: 250, y: 24), in: frame, notchInset: inset) == nil)
        #expect(MeetingControlLayout.control(at: CGPoint(x: 38, y: 80), in: frame, notchInset: inset) == nil)
    }
}
