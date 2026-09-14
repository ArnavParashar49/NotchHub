import AppKit
import NotchHubCore

/// Reports details about the frontmost app: a browser's page and tabs, a
/// coding-agent session in a terminal / editor / the Claude app, or any other
/// app's focused window title.
///
/// Reads run off the main thread (AppleScript and Accessibility calls block
/// while the other app answers), at most one at a time, every 2 s and at once
/// when the frontmost app changes. Emits only on change, and never shows one
/// app's details while another is in front.
public final class AppContextListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private let includeAgents: Bool
    private let queue = DispatchQueue(label: "notchhub.appcontext", qos: .utility)
    // Session readers, used only on `queue`.
    private let claude = AgentSessionReader<ClaudeSessionParser>(findNewest: AgentTranscripts.newestClaude)
    private let codex = AgentSessionReader<CodexSessionParser>(findNewest: AgentTranscripts.newestCodex)
    private let foxora = FoxoraSessionReader()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var last: AppContextSnapshot?
    private var inFlight = false

    public init(includeAgents: Bool, emit: @escaping (SystemEvent) -> Void) {
        self.includeAgents = includeAgents
        self.emit = emit
    }

    public var name: String { "AppContext" }

    public func start() {
        stop()
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.poll(appChanged: true)
        }
        observers.append(token)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll(appChanged: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll(appChanged: true)
    }

    public func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        last = nil
    }

    /// Reads again right away (after the island drove the browser, say).
    public func refreshSoon(after delay: TimeInterval = 0.35) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.poll(appChanged: false)
        }
    }

    private func poll(appChanged: Bool) {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else {
            publish(nil)
            return
        }
        if appChanged, last?.bundleID != bundleID {
            publish(nil)
        }
        guard !inFlight else { return }
        inFlight = true

        let pid = app.processIdentifier
        let appName = app.localizedName
        let includeAgents = self.includeAgents
        queue.async { [weak self] in
            guard let self else { return }
            let context = self.readContext(bundleID: bundleID, pid: pid, appName: appName, includeAgents: includeAgents)
            DispatchQueue.main.async {
                self.inFlight = false
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
                self.publish(context.map { AppContextSnapshot(bundleID: bundleID, context: $0) })
            }
        }
    }

    /// Runs on `queue`.
    private func readContext(bundleID: String, pid: pid_t, appName: String?, includeAgents: Bool) -> AppContext? {
        if let browser = BrowserScripting.browser(bundleID: bundleID) {
            let context = BrowserScripting.queue.sync { BrowserScripting.context(of: browser) }
            // Without scripting (e.g. Automation not allowed) a browser shows
            // just its name: its window title is the page title, often a whole
            // web address, and must not stand in for it.
            return context.map { .browser($0) }
        }
        if AppSkinRegistry.isBrowser(bundleID) {
            return nil
        }
        if includeAgents, AppSkinRegistry.isAgentHost(bundleID), let session = agentSession(for: bundleID) {
            return .agent(session)
        }
        if let title = WindowTitle.focused(pid: pid), title != appName {
            return .window(title: title)
        }
        return nil
    }

    /// Runs on `queue`. A dedicated app shows its own agent; a terminal or
    /// editor shows whichever session was active most recently.
    private func agentSession(for bundleID: String) -> AgentSession? {
        switch AppSkinRegistry.dedicatedAgent(for: bundleID) {
        case .claudeCode:
            return claude.currentSession()
        case .codex:
            return codex.currentSession()
        case .foxora:
            return foxora.currentSession()
        case nil:
            return [claude.currentSession(), codex.currentSession()]
                .compactMap { $0 }
                .max { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
        }
    }

    private func publish(_ snapshot: AppContextSnapshot?) {
        guard snapshot != last else { return }
        last = snapshot
        emit(SystemEvent(source: .frontmostApp, payload: .appContext(snapshot)))
    }
}
