import Testing
@testable import NotchHubCore

@Suite("MeetingControlLabels")
struct MeetingControlLabelsTests {

    @Test("Meet labels name the next action, so they read as the opposite state")
    func googleMeet() {
        #expect(MeetingControlLabels.interpret("Turn on microphone (⌘ + d)", app: .googleMeet) == .mute(isMuted: true))
        #expect(MeetingControlLabels.interpret("Turn off microphone", app: .googleMeet) == .mute(isMuted: false))
        #expect(MeetingControlLabels.interpret("Turn on camera (⌘ + e)", app: .googleMeet) == .camera(isOn: false))
        #expect(MeetingControlLabels.interpret("Turn off camera", app: .googleMeet) == .camera(isOn: true))
        #expect(MeetingControlLabels.interpret("Leave call", app: .googleMeet) == .leave)
        #expect(MeetingControlLabels.interpret("Turn on captions (c)", app: .googleMeet) == nil)
    }

    @Test("Zoom and Webex labels, including menu items")
    func zoomAndWebex() {
        #expect(MeetingControlLabels.interpret("Unmute Audio", app: .zoom) == .mute(isMuted: true))
        #expect(MeetingControlLabels.interpret("Mute", app: .zoom) == .mute(isMuted: false))
        #expect(MeetingControlLabels.interpret("Start Video", app: .zoom) == .camera(isOn: false))
        #expect(MeetingControlLabels.interpret("Stop Video", app: .zoom) == .camera(isOn: true))
        #expect(MeetingControlLabels.interpret("End", app: .zoom) == .leave)
        #expect(MeetingControlLabels.interpret("Unmute", app: .webex) == .mute(isMuted: true))
        #expect(MeetingControlLabels.interpret("Stop video", app: .webex) == .camera(isOn: true))
        #expect(MeetingControlLabels.interpret("Leave meeting", app: .webex) == .leave)
    }

    @Test("controls aimed at other people never read as your own")
    func othersIgnored() {
        #expect(MeetingControlLabels.interpret("Mute All", app: .zoom) == nil)
        #expect(MeetingControlLabels.interpret("Mute everyone", app: .webex) == nil)
        #expect(MeetingControlLabels.interpret("Mute notifications", app: .teams) == nil)
        #expect(MeetingControlLabels.interpret("Muted", app: .zoom) == nil)
        #expect(MeetingControlLabels.interpret("", app: .zoom) == nil)
    }

    @Test("Webex is a call app with its own shortcuts")
    func webexApp() {
        #expect(MeetingApp.webex.bundleIDs.contains("Cisco-Systems.Spark"))
        #expect(MeetingApp.webex.shortcut(for: .mute) == KeyChord(keyCode: KeyChord.Key.m, shift: true))
        #expect(!MeetingApp.webex.isBrowserHosted)
    }
}
