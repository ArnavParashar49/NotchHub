import AppKit
import NotchHubCore
import NotchHubSystem
import UniformTypeIdentifiers

/// "Keep working with the lid closed" (Settings → Lid), in the coordinator.
///
/// `LidAwakeController` (NotchHubSystem) does the system work and owns the
/// truth about the Mac's sleep; this extension starts it on a normal launch,
/// hands it the page's taps (and the dashboard lid chip's, which is the same
/// tap on the switch), builds the page's app lists from NSWorkspace, and
/// redraws Settings or the open dashboard when the controller says something
/// changed. The compact island never changes for the feature — no width, no
/// glyph: outside its own page there is a small bolt on the features page's
/// Lid card, and the lid chip on the dashboard's quick-action bar.
///
/// While NotchHub holds SleepDisabled, SIGTERM (`kill`, `killall`) is turned
/// into an ordinary quit, so `applicationWillTerminate` puts sleep back
/// rather than the process dying with the Mac unable to sleep; otherwise the
/// signal is left alone. A crash, Force Quit or SIGKILL is put right by the
/// controller's dead-man's switch (a small `/bin/sh` that outlives NotchHub
/// and runs the helper's `disablesleep 0`), and the next launch reconciles.
extension NotchHubApp {

    /// Starts the controller (a normal launch only).
    func startLidAwake() {
        guard lidAwake == nil else { return }
        let controller = LidAwakeController()
        controller.onChange = { [weak self] in self?.lidChanged() }
        lidAwake = controller
        controller.start()
        log("lid: started")
    }

    /// What Settings → Lid shows. Without the controller (an inspection
    /// launch) the saved settings are shown, not live.
    var lidSettings: LidSettingsModel {
        lidAwake?.model ?? LidSettingsModel(settings: LidAwakeSettings.load(), status: .notManaged)
    }

    /// The controller said something on the page changed: redraw whatever
    /// shows it — Settings, or the dashboard's lid chip.
    func lidChanged() {
        syncLidTerminateSignal()
        if panel == .settings || currentIslandState() == .interactive { refreshPanel() }
    }

    /// A tap in Settings → Lid, or the dashboard's lid chip (which sends
    /// the main switch's own `.setEnabled`).
    func lidIntent(_ intent: LidIntent) {
        guard lidSettings.isEnabled(intent) else { return }
        log("lid: settings → \(intent)")
        if intent == .chooseApp {
            chooseLidApps()
        } else {
            lidAwake?.handle(intent)
        }
    }

    // MARK: - Apps

    /// The chosen apps (by bundle identifier, named and drawn from wherever
    /// that app is installed) and the running apps that could be added.
    func lidAppChoices() -> LidAppChoices {
        let chosen = lidSettings.settings.apps
        let running = NSWorkspace.shared.runningApplications
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        let rows = chosen.map { bundleID -> LidAppRow in
            if let app = running.first(where: { $0.bundleIdentifier == bundleID }) {
                return LidAppRow(bundleID: bundleID, name: app.localizedName ?? bundleID, icon: app.icon, isOpen: true)
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return LidAppRow(bundleID: bundleID, name: Self.appName(at: url), icon: NSWorkspace.shared.icon(forFile: url.path),
                                 isOpen: runningIDs.contains(bundleID))
            }
            return LidAppRow(bundleID: bundleID, name: bundleID, icon: nil, isOpen: runningIDs.contains(bundleID))
        }
        let own = Bundle.main.bundleIdentifier
        var seen = Set(chosen)
        let candidates = running
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> LidAppRow? in
                guard let id = app.bundleIdentifier, id != own, seen.insert(id).inserted else { return nil }
                return LidAppRow(bundleID: id, name: app.localizedName ?? id, icon: app.icon, isOpen: true)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return LidAppChoices(chosen: rows, candidates: candidates)
    }

    private static func appName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// "Choose from Applications…": any app, running or not.
    private func chooseLidApps() {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.prompt = "Add"
        openPanel.message = "Keep your Mac working with the lid closed while these apps are open."
        openPanel.begin { [weak self] response in
            guard let self, response == .OK else { return }
            for url in openPanel.urls {
                guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                    self.log("lid: \(url.lastPathComponent) has no bundle identifier")
                    continue
                }
                self.lidAwake?.handle(.addApp(bundleID: bundleID))
            }
        }
    }

    // MARK: - SIGTERM

    private func syncLidTerminateSignal() {
        // The record is written before sleep is turned off: covered from then.
        let holds = lidAwake?.engine.record.ownsSleepDisabled == true
        if holds, lidTerminateSignal == nil {
            signal(SIGTERM, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            source.setEventHandler { [weak self] in
                self?.log("lid: SIGTERM — quitting so normal sleep goes back")
                NSApp.terminate(nil)
            }
            source.resume()
            lidTerminateSignal = source
        } else if !holds, let source = lidTerminateSignal {
            source.cancel()
            lidTerminateSignal = nil
            signal(SIGTERM, SIG_DFL)
        }
    }
}
