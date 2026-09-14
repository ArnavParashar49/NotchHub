import Testing
@testable import NotchHubCore

@Suite("Google Meet")
struct GoogleMeetTests {

    @Test("only a call address counts as a Meet call")
    func callURLs() {
        #expect(MeetingLink.googleMeetCall(in: "https://meet.google.com/xyz-wxyz-xyz") == "https://meet.google.com/xyz-wxyz-xyz")
        #expect(MeetingLink.googleMeetCall(in: "https://meet.google.com/xyz-wxyz-xyz?authuser=0&hl=en") == "https://meet.google.com/xyz-wxyz-xyz")
        #expect(MeetingLink.googleMeetCall(in: "https://meet.google.com/") == nil)
        #expect(MeetingLink.googleMeetCall(in: "https://meet.google.com/landing") == nil)
        #expect(MeetingLink.googleMeetCall(in: "https://example.com/xyz-wxyz-xyz") == nil)
    }

    @Test("a browser is in a call only while it captures the microphone")
    func browserCapture() {
        #expect(MeetingDetector.browserCapturingAudio("com.google.Chrome", inputBundleIDs: ["com.google.Chrome.helper"], microphoneInUse: true))
        #expect(!MeetingDetector.browserCapturingAudio("com.google.Chrome", inputBundleIDs: ["us.zoom.xos"], microphoneInUse: true))
        #expect(MeetingDetector.browserCapturingAudio("company.thebrowser.Browser", inputBundleIDs: ["company.thebrowser.browser.helper"], microphoneInUse: false))
        #expect(MeetingDetector.browserCapturingAudio("com.apple.Safari", inputBundleIDs: ["com.apple.WebKit.GPU"], microphoneInUse: false))
        #expect(MeetingDetector.browserCapturingAudio("com.google.Chrome", inputBundleIDs: nil, microphoneInUse: true))
        #expect(!MeetingDetector.browserCapturingAudio("com.google.Chrome", inputBundleIDs: nil, microphoneInUse: false))
    }

    @Test("Meet's shortcuts: ⌘D mute, ⌘E camera")
    func shortcuts() {
        #expect(MeetingApp.googleMeet.shortcut(for: .mute) == KeyChord(keyCode: KeyChord.Key.d))
        #expect(MeetingApp.googleMeet.shortcut(for: .camera) == KeyChord(keyCode: KeyChord.Key.e))
    }
}
