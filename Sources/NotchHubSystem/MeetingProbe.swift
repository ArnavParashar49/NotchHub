import AppKit
import NotchHubCore

/// A diagnostic: what the Accessibility scan reads from the call apps and
/// Meet windows that are open right now. Backs `NotchHub --meeting-probe`.
/// Reports only the matched controls' state, never other window content.
public enum MeetingProbe {

    public struct Result: Sendable {
        public let app: String
        public let window: String
        public let inCall: Bool?
        public let isMuted: Bool?
        public let isCameraOn: Bool?
        public let hasLeave: Bool
    }

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public static func run() -> [Result] {
        var results: [Result] = []
        let apps = NSWorkspace.shared.runningApplications
        for app in MeetingApp.allCases where !app.isBrowserHosted {
            guard let running = apps.first(where: { $0.bundleIdentifier.map(app.bundleIDs.contains) ?? false }),
                  let snapshot = MeetingAccessibility.snapshot(pid: running.processIdentifier, app: app, windowTitle: nil) else { continue }
            results.append(Result(app: app.name, window: "app", inCall: snapshot.inCall, isMuted: snapshot.isMuted, isCameraOn: snapshot.isCameraOn, hasLeave: snapshot.leave != nil))
        }
        for browser in BrowserScripting.all {
            guard let running = apps.first(where: { $0.bundleIdentifier == browser.bundleID }) else { continue }
            // Window titles of a browser show the active tab: Meet's are
            // "Meet – abc-defg-hij" or the meeting's name after "Meet".
            for title in ["Meet –", "Meet -", "Meet"] {
                guard let snapshot = MeetingAccessibility.snapshot(pid: running.processIdentifier, app: .googleMeet, windowTitle: title),
                      snapshot.windowFound else { continue }
                results.append(Result(app: "Google Meet in \(browser.appName)", window: "title contains \"\(title)\"", inCall: snapshot.inCall, isMuted: snapshot.isMuted, isCameraOn: snapshot.isCameraOn, hasLeave: snapshot.leave != nil))
                break
            }
        }
        return results
    }
}
