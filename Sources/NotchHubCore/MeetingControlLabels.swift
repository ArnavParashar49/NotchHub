import Foundation

/// What a call control's label says about the call.
public enum MeetingControlReading: Equatable, Sendable {
    /// A microphone control; `isMuted` is the microphone's CURRENT state.
    case mute(isMuted: Bool)
    /// A camera control; `isOn` is the camera's CURRENT state.
    case camera(isOn: Bool)
    /// The control that leaves or ends the call.
    case leave
}

/// Reads call state from the labels of a call app's own buttons and menu
/// items, as Accessibility reports them.
///
/// A button is labelled with the action it WILL perform, which is the opposite
/// of the current state: Meet's "Turn on microphone" means the mic is off, and
/// Zoom's "Unmute" means you are muted. Labels are matched whole (or as a
/// leading phrase), per app, so "Mute everyone" or "Mute all" in a host panel
/// never reads as your own microphone.
public enum MeetingControlLabels {

    struct Phrases {
        var muted: [String]
        var unmuted: [String]
        var cameraOff: [String]
        var cameraOn: [String]
        var leave: [String]
    }

    static func phrases(for app: MeetingApp) -> Phrases {
        switch app {
        case .googleMeet:
            return Phrases(
                muted: ["turn on microphone"],
                unmuted: ["turn off microphone"],
                cameraOff: ["turn on camera"],
                cameraOn: ["turn off camera"],
                leave: ["leave call"]
            )
        case .zoom:
            return Phrases(
                muted: ["unmute", "unmute audio", "unmute my audio", "unmute microphone"],
                unmuted: ["mute", "mute audio", "mute my audio", "mute microphone"],
                cameraOff: ["start video", "start my video", "start camera"],
                cameraOn: ["stop video", "stop my video", "stop camera"],
                leave: ["leave", "leave meeting", "end", "end meeting"]
            )
        case .teams:
            return Phrases(
                muted: ["unmute", "unmute mic", "unmute microphone"],
                unmuted: ["mute", "mute mic", "mute microphone"],
                cameraOff: ["turn camera on", "turn on camera", "start video"],
                cameraOn: ["turn camera off", "turn off camera", "stop video"],
                leave: ["leave", "hang up", "leave meeting"]
            )
        case .webex:
            return Phrases(
                muted: ["unmute", "unmute audio", "unmute me"],
                unmuted: ["mute", "mute audio", "mute me"],
                cameraOff: ["start video", "turn on video", "start my video"],
                cameraOn: ["stop video", "turn off video", "stop my video"],
                leave: ["leave", "leave meeting", "end meeting", "end"]
            )
        }
    }

    /// Words that mark a control as acting on someone other than you.
    static let othersWords: Set<String> = ["all", "everyone", "participant", "participants", "others", "notifications", "chat"]

    public static func interpret(_ label: String, app: MeetingApp) -> MeetingControlReading? {
        let text = normalize(label)
        guard !text.isEmpty else { return nil }
        let words = Set(text.split(separator: " ").map(String.init))
        guard words.isDisjoint(with: othersWords) else { return nil }

        func matches(_ phrases: [String]) -> Bool {
            phrases.contains { text == $0 || text.hasPrefix($0 + " ") }
        }
        let table = phrases(for: app)
        if matches(table.muted) { return .mute(isMuted: true) }
        if matches(table.unmuted) { return .mute(isMuted: false) }
        if matches(table.cameraOff) { return .camera(isOn: false) }
        if matches(table.cameraOn) { return .camera(isOn: true) }
        if matches(table.leave) { return .leave }
        return nil
    }

    /// Lower-cased, shortcut hints like "(⌘ + d)" removed, trimmed.
    static func normalize(_ label: String) -> String {
        var text = label.lowercased()
        if let paren = text.firstIndex(of: "(") {
            text = String(text[..<paren])
        }
        text = text.replacingOccurrences(of: "…", with: "")
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }
}
