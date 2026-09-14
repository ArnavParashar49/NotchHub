import Foundation
import NotchHubCore

/// Reads and drives the frontmost browser through AppleScript (the Automation
/// permission). Scripts fetch whole lists in one Apple event per property, and
/// all scripting runs on one serial queue.
public enum BrowserScripting {

    public struct Browser: Equatable, Sendable {
        public enum Dictionary: Sendable { case chromium, safari, arc }
        public let bundleID: String
        public let appName: String
        public let dictionary: Dictionary
    }

    public static let all: [Browser] = [
        Browser(bundleID: "com.google.Chrome", appName: "Google Chrome", dictionary: .chromium),
        Browser(bundleID: "com.brave.Browser", appName: "Brave Browser", dictionary: .chromium),
        Browser(bundleID: "com.microsoft.edgemac", appName: "Microsoft Edge", dictionary: .chromium),
        Browser(bundleID: "com.vivaldi.Vivaldi", appName: "Vivaldi", dictionary: .chromium),
        Browser(bundleID: "com.operasoftware.Opera", appName: "Opera", dictionary: .chromium),
        Browser(bundleID: "ai.perplexity.comet", appName: "Comet", dictionary: .chromium),
        Browser(bundleID: "company.thebrowser.Browser", appName: "Arc", dictionary: .arc),
        Browser(bundleID: "com.apple.Safari", appName: "Safari", dictionary: .safari),
    ]

    public static func browser(bundleID: String) -> Browser? {
        all.first { $0.bundleID == bundleID }
    }

    /// Serial: `NSAppleScript` must never run concurrently with itself here.
    static let queue = DispatchQueue(label: "notchhub.browser.scripting", qos: .userInitiated)

    /// The front window's page and tabs. Blocking — call on `queue`.
    static func context(of browser: Browser) -> BrowserContext? {
        let activeTab = browser.dictionary == .safari ? "current tab" : "active tab"
        let title = browser.dictionary == .safari ? "name" : "title"
        let script = """
        tell application "\(browser.appName)"
            if (count of windows) is 0 then return ""
            set w to front window
            set activeURL to URL of \(activeTab) of w
            set activeTitle to \(title) of \(activeTab) of w
            set urlList to URL of every tab of w
            set titleList to \(title) of every tab of w
        end tell
        set AppleScript's text item delimiters to (character id 31)
        set urlText to urlList as text
        set titleText to titleList as text
        set AppleScript's text item delimiters to ""
        return (activeTitle as text) & (character id 30) & (activeURL as text) & (character id 30) & urlText & (character id 30) & titleText
        """
        guard let output = run(script) else { return nil }
        let parts = output.components(separatedBy: "\u{1E}")
        guard parts.count == 4 else { return nil }
        return BrowserContext.from(
            activeTitle: parts[0],
            activeURL: parts[1],
            titles: parts[3].components(separatedBy: "\u{1F}"),
            urls: parts[2].components(separatedBy: "\u{1F}")
        )
    }

    /// Switches the front window to a tab (1-based). Asynchronous.
    public static func selectTab(bundleID: String, index: Int, completion: (@Sendable () -> Void)? = nil) {
        guard let browser = browser(bundleID: bundleID) else { return }
        let script: String
        switch browser.dictionary {
        case .chromium:
            script = "tell application \"\(browser.appName)\" to set active tab index of front window to \(index)"
        case .safari:
            script = "tell application \"Safari\" to set current tab of front window to tab \(index) of front window"
        case .arc:
            script = "tell application \"Arc\" to tell tab \(index) of front window to select"
        }
        queue.async {
            _ = run(script)
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        guard error == nil, let value = output.stringValue, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Actions

    /// Performs a navigation action through the browser's own scripting
    /// (Automation permission only — no Accessibility). Calls back on the main
    /// queue with `false` when the browser has no such command or refuses, so
    /// the caller can fall back to the keyboard shortcut.
    public static func perform(_ action: BrowserAction, bundleID: String, completion: @escaping @Sendable (Bool) -> Void) {
        guard let browser = browser(bundleID: bundleID), let script = actionScript(action, browser: browser) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        queue.async {
            let ok = runCommand(script)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    static func actionScript(_ action: BrowserAction, browser: Browser) -> String? {
        let app = "tell application \"\(browser.appName)\""
        switch (browser.dictionary, action) {
        case (.chromium, .back), (.arc, .back):
            return "\(app) to tell active tab of front window to go back"
        case (.chromium, .forward), (.arc, .forward):
            return "\(app) to tell active tab of front window to go forward"
        case (.chromium, .reload), (.arc, .reload):
            return "\(app) to tell active tab of front window to reload"
        case (.chromium, .newTab), (.arc, .newTab):
            return "\(app) to make new tab at end of tabs of front window"
        case (.safari, .reload):
            return "\(app) to set URL of current tab of front window to (URL of current tab of front window)"
        case (.safari, .newTab):
            return "\(app) to tell front window to set current tab to (make new tab)"
        case (.safari, .back):
            // Needs Safari's "Allow JavaScript from Apple Events"; otherwise the
            // caller falls back to ⌘[.
            return "\(app) to do JavaScript \"history.back()\" in current tab of front window"
        case (.safari, .forward):
            return "\(app) to do JavaScript \"history.forward()\" in current tab of front window"
        case (_, .selectTab):
            return nil
        }
    }

    // MARK: - Every tab

    /// One tab anywhere in a browser (1-based window and tab indices).
    public struct TabLocation: Equatable, Sendable {
        public let window: Int
        public let tab: Int
        public let url: String
        public let title: String
    }

    /// Every tab of every window. Blocking — call on `queue`.
    static func allTabs(of browser: Browser) -> [TabLocation] {
        let title = browser.dictionary == .safari ? "name" : "title"
        let script = """
        tell application "\(browser.appName)"
            if (count of windows) is 0 then return ""
            set urlLists to URL of every tab of every window
            set titleLists to \(title) of every tab of every window
        end tell
        set parts to {}
        set AppleScript's text item delimiters to (character id 31)
        repeat with i from 1 to count of urlLists
            set end of parts to ((item i of urlLists) as text) & (character id 30) & ((item i of titleLists) as text)
        end repeat
        set AppleScript's text item delimiters to (character id 29)
        set joined to parts as text
        set AppleScript's text item delimiters to ""
        return joined
        """
        guard let output = run(script) else { return [] }
        var result: [TabLocation] = []
        for (w, window) in output.components(separatedBy: "\u{1D}").enumerated() {
            let halves = window.components(separatedBy: "\u{1E}")
            guard halves.count == 2 else { continue }
            let urls = halves[0].components(separatedBy: "\u{1F}")
            let titles = halves[1].components(separatedBy: "\u{1F}")
            for t in 0..<min(urls.count, titles.count) {
                result.append(TabLocation(window: w + 1, tab: t + 1, url: urls[t], title: titles[t]))
            }
        }
        return result
    }

    /// Brings a tab to the front — its window raised, the tab selected, the
    /// browser activated. Asynchronous; calls back on main with success.
    public static func focusTab(bundleID: String, matching url: String, completion: @escaping @Sendable (Bool) -> Void) {
        withTab(bundleID: bundleID, matching: url, completion: completion) { browser, location in
            focusScript(browser, location)
        }
    }

    /// Brings a tab forward. Blocking — call on `queue`.
    static func focus(_ browser: Browser, matching url: String) -> Bool {
        guard let location = allTabs(of: browser).first(where: { $0.url.hasPrefix(url) }) else { return false }
        return runCommand(focusScript(browser, location))
    }

    static func focusScript(_ browser: Browser, _ location: TabLocation) -> String {
        let select: String
        switch browser.dictionary {
        case .chromium: select = "set active tab index of window \(location.window) to \(location.tab)"
        case .safari: select = "set current tab of window \(location.window) to tab \(location.tab) of window \(location.window)"
        case .arc: select = "tell tab \(location.tab) of window \(location.window) to select"
        }
        return """
        tell application "\(browser.appName)"
            \(select)
            set index of window \(location.window) to 1
            activate
        end tell
        """
    }

    /// Closes a tab. Asynchronous; calls back on main with success.
    public static func closeTab(bundleID: String, matching url: String, completion: @escaping @Sendable (Bool) -> Void) {
        withTab(bundleID: bundleID, matching: url, completion: completion) { browser, location in
            "tell application \"\(browser.appName)\" to close tab \(location.tab) of window \(location.window)"
        }
    }

    private static func withTab(
        bundleID: String,
        matching url: String,
        completion: @escaping @Sendable (Bool) -> Void,
        script: @escaping (Browser, TabLocation) -> String
    ) {
        guard let browser = browser(bundleID: bundleID) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        queue.async {
            guard let location = allTabs(of: browser).first(where: { $0.url.hasPrefix(url) }) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let ok = runCommand(script(browser, location))
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Runs a script that returns nothing; success means no error.
    private static func runCommand(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }
}

