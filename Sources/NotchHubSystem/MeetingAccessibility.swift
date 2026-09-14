import AppKit
import ApplicationServices
import NotchHubCore

/// Reads a call's state from — and presses — the call app's own controls
/// through Accessibility: its window buttons and menu items (Zoom, Teams,
/// Webex), or the call page's buttons in the browser window showing it (Meet).
/// Pressing an element needs no keyboard focus, so it never steals the user's
/// app. Everything here blocks on inter-process calls: use off the main thread.
enum MeetingAccessibility {

    struct Snapshot {
        var isMuted: Bool?
        var isCameraOn: Bool?
        var mute: AXUIElement?
        var camera: AXUIElement?
        var leave: AXUIElement?
        /// Whether the call's window was found at all. Without it, a missing
        /// Leave button means "unknown", not "not in a call".
        var windowFound = false

        /// Whether the call is live, when that can be told.
        var inCall: Bool? {
            windowFound ? (leave != nil || mute != nil) : nil
        }

        func element(for control: MeetingControl) -> AXUIElement? {
            switch control {
            case .mute: return mute
            case .camera: return camera
            case .leave: return leave
            }
        }
    }

    /// Nodes visited per scan — a call page is large, but its controls are
    /// found long before this.
    static let nodeBudget = 9_000

    /// Scans the app for call controls. `nil` without Accessibility permission.
    /// For a browser, `windowTitle` (the call tab's title) picks the window.
    static func snapshot(pid: pid_t, app: MeetingApp, windowTitle: String?) -> Snapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)

        var snapshot = Snapshot()
        var roots: [AXUIElement] = []
        if app.isBrowserHosted {
            // Chromium builds its web accessibility tree only when asked.
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            let wanted = (windowTitle ?? "").lowercased()
            for window in elements(application, kAXWindowsAttribute) {
                let title = (string(window, kAXTitleAttribute) ?? "").lowercased()
                guard !wanted.isEmpty, !title.isEmpty, title.contains(wanted) || wanted.contains(title) else { continue }
                roots.append(window)
            }
            snapshot.windowFound = !roots.isEmpty
        } else {
            let windows = elements(application, kAXWindowsAttribute)
            snapshot.windowFound = !windows.isEmpty
            roots.append(contentsOf: windows)
            if let menuBar = element(application, kAXMenuBarAttribute) {
                roots.append(menuBar)
            }
        }

        let controlRoles: Set<String> = [kAXButtonRole, kAXMenuItemRole, kAXCheckBoxRole, "AXToggle", "AXPopUpButton"]
        var budget = nodeBudget
        var stack: [(element: AXUIElement, depth: Int)] = roots.reversed().map { ($0, 0) }
        while let item = stack.popLast(), budget > 0 {
            budget -= 1
            let role = string(item.element, kAXRoleAttribute) ?? ""
            if controlRoles.contains(role) {
                record(item.element, app: app, into: &snapshot)
                if snapshot.mute != nil, snapshot.camera != nil, snapshot.leave != nil { break }
                if role != kAXMenuItemRole { continue } // a button's children are its glyphs
            }
            guard item.depth < 64 else { continue }
            for child in elements(item.element, kAXChildrenAttribute).reversed() {
                stack.append((child, item.depth + 1))
            }
        }
        return snapshot
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    // MARK: - Helpers

    private static func record(_ element: AXUIElement, app: MeetingApp, into snapshot: inout Snapshot) {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            guard let label = string(element, attribute),
                  let reading = MeetingControlLabels.interpret(label, app: app) else { continue }
            switch reading {
            case let .mute(isMuted):
                guard snapshot.mute == nil else { return }
                snapshot.mute = element
                snapshot.isMuted = isMuted
            case let .camera(isOn):
                guard snapshot.camera == nil else { return }
                snapshot.camera = element
                snapshot.isCameraOn = isOn
            case .leave:
                guard snapshot.leave == nil else { return }
                snapshot.leave = element
            }
            return
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap { object in
            CFGetTypeID(object) == AXUIElementGetTypeID() ? unsafeBitCast(object, to: AXUIElement.self) : nil
        }
    }
}

/// Presses a call's controls for the island.
public enum MeetingControlDriver {

    private static let queue = DispatchQueue(label: "notchhub.meeting.controls", qos: .userInitiated)

    /// Presses `control` in the call's own UI. Calls back on the main queue
    /// with whether it was pressed; `false` (no Accessibility, or no such
    /// control on screen) lets the caller fall back to a keyboard shortcut.
    public static func press(_ control: MeetingControl, in meeting: Meeting, completion: @escaping @Sendable (Bool) -> Void) {
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        queue.async {
            var pressed = attempt(control, in: meeting)
            if !pressed, focusBrowserTab(of: meeting) {
                // The call tab was in the background, so its page had no
                // accessible controls. Bring it forward and try once more.
                Thread.sleep(forTimeInterval: 0.5)
                pressed = attempt(control, in: meeting)
            }
            DispatchQueue.main.async { completion(pressed) }
        }
    }

    private static func attempt(_ control: MeetingControl, in meeting: Meeting) -> Bool {
        guard let pid = processID(for: meeting) else { return false }
        let title = meeting.browserBundleID == nil ? nil : tabTitle(of: meeting)
        guard let element = MeetingAccessibility.snapshot(pid: pid, app: meeting.app, windowTitle: title)?.element(for: control) else {
            return false
        }
        return MeetingAccessibility.press(element)
    }

    private static func processID(for meeting: Meeting) -> pid_t? {
        let ids = meeting.browserBundleID.map { [$0] } ?? meeting.app.bundleIDs
        return NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier.map(ids.contains) ?? false }?
            .processIdentifier
    }

    private static func tabTitle(of meeting: Meeting) -> String? {
        guard let browserID = meeting.browserBundleID, let url = meeting.callURL,
              let browser = BrowserScripting.browser(bundleID: browserID) else { return nil }
        return BrowserScripting.queue.sync {
            BrowserScripting.allTabs(of: browser).first { $0.url.hasPrefix(url) }?.title
        }
    }

    private static func focusBrowserTab(of meeting: Meeting) -> Bool {
        guard let browserID = meeting.browserBundleID, let url = meeting.callURL,
              let browser = BrowserScripting.browser(bundleID: browserID) else { return false }
        return BrowserScripting.queue.sync { BrowserScripting.focus(browser, matching: url) }
    }
}
