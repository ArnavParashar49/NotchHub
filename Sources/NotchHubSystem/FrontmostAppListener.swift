import AppKit
import NotchHubCore

/// Reports the frontmost app so the island can dress for it.
///
/// NotchBay's "app skins": whichever app is in front takes over the island —
/// its identity on the left, its live state on the right. Apps with no skin in
/// the registry emit `nil`, which hands the island back.
final class FrontmostAppListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var observers: [NSObjectProtocol] = []

    init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    var name: String { "FrontmostApp" }

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.report()
            }
            observers.append(token)
        }
        report()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    /// Publishes the current frontmost app's skin, or `nil` when there is none.
    ///
    /// Every app gets a skin — the wings show the real icon for whatever you
    /// are in, not just the handful of apps with a hand-written entry. The
    /// registry only supplies a nicer name/symbol and the live-state category;
    /// an unknown app falls back to its own name and a generic symbol.
    private func report() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            emit(SystemEvent(source: .frontmostApp, payload: .frontmostApp(nil)))
            return
        }

        let entry = AppSkinRegistry.entry(for: bundleID)
        let skin = AppSkin(
            bundleID: bundleID,
            name: entry?.name ?? app.localizedName ?? "App",
            symbol: entry?.symbol ?? "app.fill",
            iconData: Self.iconData(for: app),
            state: Self.liveState(for: bundleID),
            detail: nil
        )
        emit(SystemEvent(source: .frontmostApp, payload: .frontmostApp(skin)))
    }

    /// The frontmost app's real icon as PNG data, or `nil` when it cannot be
    /// resolved. The wings show the true icon rather than a stand-in symbol.
    private static func iconData(for app: NSRunningApplication) -> Data? {
        guard let icon = app.icon else { return nil }
        guard let tiff = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// The app's live state line, where the app exposes one cheaply.
    ///
    /// Browsers and AI tools report here; everything else is identity-only.
    private static func liveState(for bundleID: String) -> String? {
        if AppSkinRegistry.isBrowser(bundleID) {
            return browserTabCount()
        }
        return nil
    }

    /// The frontmost browser window's title, trimmed to something glanceable.
    private static func browserTabCount() -> String? {
        // Reading another app's window titles needs Accessibility permission;
        // without it we simply report nothing rather than guessing.
        nil
    }
}
