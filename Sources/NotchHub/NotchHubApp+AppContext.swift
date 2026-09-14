import AppKit
import ApplicationServices
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// Details about the frontmost app: its hover strip, and the browser controls.
extension NotchHubApp {

    /// The frontmost app's details — only when they describe the app that is
    /// actually in front, so a stale reading never shows for another app.
    var currentAppContext: AppContextSnapshot? {
        guard let appContext, appContext.bundleID == skin?.bundleID else { return nil }
        return appContext
    }

    /// The hover strip for the frontmost app, when it has more to say than its
    /// icon.
    func appStrip() -> AppStrip? {
        guard let skin, let context = currentAppContext?.context else { return nil }
        switch context {
        case .browser:
            // The strip names the browser. The page and its address belong in
            // the browser's panel, never in the notch-height bar.
            return AppStrip(label: skin.name, trailing: .browserControls)
        case let .agent(session):
            return AppStrip(
                label: session.model ?? session.tool,
                trailing: .agent(tokens: AgentFormat.tokens(session.tokens), isWorking: session.isWorking)
            )
        case let .window(title):
            guard let label = AppStripLabel.windowTitle(title, appName: skin.name) else { return nil }
            return AppStrip(label: label, trailing: .status)
        }
    }

    /// Handles a click on the hover strip's browser buttons.
    func wingsControlHit(at point: NSPoint) -> Bool {
        guard currentIslandState() == .wings,
              case .browserControls? = appStrip()?.trailing else { return false }
        let frame = window.localFrame(for: .wings, content: islandModel.contentSize)
        guard let action = WingControlLayout.browserAction(
            at: point,
            in: frame,
            notchWidth: window.notchWidth,
            inset: DesignTokens.wingInset,
            trailingReserve: petBarReserve
        ) else { return false }
        performBrowserAction(action)
        return true
    }

    /// Drives the frontmost browser: navigation through its own keyboard
    /// shortcuts (needs Accessibility), tab switching through scripting.
    func performBrowserAction(_ action: BrowserAction) {
        guard let bundleID = currentAppContext?.bundleID,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return
        }
        log("browser: \(action)")
        switch action {
        case let .selectTab(index):
            BrowserScripting.selectTab(bundleID: bundleID, index: index) { [weak self] in
                Task { @MainActor in self?.monitor?.refreshAppContext() }
            }
        default:
            // The browser's own scripting first: it needs only the Automation
            // permission. Keystrokes (Accessibility) are the fallback for
            // browsers or commands scripting cannot do.
            let pid = app.processIdentifier
            BrowserScripting.perform(action, bundleID: bundleID) { [weak self] ok in
                Task { @MainActor in
                    guard let self else { return }
                    if !ok {
                        guard let chord = action.shortcut, self.requestAccessibility(for: "browser controls") else { return }
                        Self.post(chord, to: pid)
                    }
                    self.monitor?.refreshAppContext()
                }
            }
        }
    }

    /// Whether NotchHub may send keystrokes to other apps. Without the
    /// permission it shows the system prompt once and reports `false`.
    func requestAccessibility(for purpose: String) -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        log("\(purpose): Accessibility permission needed")
        return false
    }

    // MARK: - App panel

    /// Whether the frontmost app has its own panel to open on a click.
    var appPanelAvailable: Bool {
        switch currentAppContext?.context {
        case .browser?, .agent?: return true
        case .window?, nil: return false
        }
    }

    /// The panel's height: taller for an agent that reports plan limits.
    func appPanelHeight() -> CGFloat {
        guard case let .agent(session)? = currentAppContext?.context else { return NotchGeometry.appPanelHeight }
        return NotchGeometry.appPanelHeight + CGFloat(min(session.limits.count, 2)) * AgentPanelView.limitRowHeight
    }

    func appPanelContent() -> AnyView? {
        guard let skin, let context = currentAppContext?.context else { return nil }
        switch context {
        case let .browser(browser):
            return AnyView(BrowserPanelView(
                notchInset: window.notchHeight,
                appName: skin.name,
                iconData: skin.iconData,
                browser: browser
            ))
        case let .agent(session):
            return AnyView(AgentPanelView(
                notchInset: window.notchHeight,
                iconData: skin.iconData,
                session: session
            ))
        case .window:
            return nil
        }
    }

    /// Handles a click on an app panel's controls. A miss falls through to
    /// the island click, which closes the panel.
    func appPanelControlHit(at point: NSPoint) -> Bool {
        guard currentIslandState() == .appPanel else { return false }
        let frame = window.localFrame(for: .appPanel, content: islandModel.contentSize)
        var tabs: [BrowserTab]?
        if case let .browser(browser)? = currentAppContext?.context {
            tabs = browser.nearbyTabs(limit: AppPanelLayout.maxTabCards)
        }
        guard let action = AppPanelLayout.action(at: point, in: frame, notchInset: window.notchHeight, browserTabs: tabs) else {
            return false
        }
        log("appPanel: \(action)")
        switch action {
        case .dashboard:
            showsDashboardOverApp = true
            renderIsland()
        case .settings:
            closeDashboard()
            toggleSettings()
            renderIsland()
        case let .browser(browserAction):
            performBrowserAction(browserAction)
        }
        return true
    }
}

