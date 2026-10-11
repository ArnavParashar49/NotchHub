import AppKit
import NotchHubCore
import NotchHubSystem

/// NEO.app's menu, in NotchHub's Settings.
///
/// While the notch hosts NEO, NEO.app keeps no menu-bar item: the NEO
/// section of Settings shows what that menu showed and does what it did.
/// The section is a view of `NeoSettingsModel` and sends `NeoSettingsIntent`s
/// here — nothing else. What NEO.app must do goes out through the monitor to
/// the one thing that talks to NEO, its listener (`SystemMonitor.neoShell`);
/// what the host does itself — its own panel, launching NEO.app, opening
/// System Settings — is done here. NEO.app's answers come back the way all
/// of NEO's facts do: through the listener, as `neoShell` events.
///
/// One row is not the menu's: "Listen for 'Neo'", a setting of NEO's core
/// (the microphone always on for the wake word, or closed until NEO is
/// summoned with its keys). The tap asks the core to switch it
/// (`SystemMonitor.neoSet`); the switch moves when the core says it did
/// (`neoSettings` events) — never on the tap alone, so it always shows what
/// the microphone is really doing.
extension NotchHubApp {

    /// What the NEO section shows right now.
    var neoSettings: NeoSettingsModel {
        NeoSettingsModel(
            // The panel's own model: it moves on the tap, before the feature set does.
            featureOn: panel == .settings ? settingsModel.neo : featureSettings.isEnabled(.neo),
            connected: neoPresence.isConnected,
            shell: neoShellStatus,
            core: neoCoreSettings
        )
    }

    /// NEO's core said where its settings stand (on connecting, and whenever
    /// one is switched — here, or anywhere else).
    func neoCoreSettingsReceived(_ settings: NeoCoreSettings) {
        guard settings != neoCoreSettings else { return }
        neoCoreSettings = settings
        log("neo settings received (wake word: \(settings.wakeWord.map { $0 ? "on" : "off" } ?? "unknown"), check-ins: \(settings.wellbeingCheckins.map { $0 ? "on" : "off" } ?? "unknown"))")
        if panel == .settings { refreshPanel() }
    }

    /// NEO.app's shell reported (on connecting, and whenever it changes: a
    /// permission granted, the login item switched).
    func neoShellReceived(_ status: NeoShellStatus) {
        guard status != neoShellStatus else { return }
        neoShellStatus = status
        if panel == .settings { refreshPanel() }
    }

    /// A tap in the NEO section.
    func neoSettingsIntent(_ intent: NeoSettingsIntent) {
        guard neoSettings.isEnabled(intent) else { return }
        log("neo: settings → \(intent)")
        switch intent {
        case .openChat:
            openNeoChat()
        case .start:
            startNeoApp()
        case let .openPermission(permission):
            if let url = URL(string: permission.settingsURL) { NSWorkspace.shared.open(url) }
        case .apiKeys, .openLogs, .restart, .eraseMemory, .openAtLogin, .quit:
            // NEO.app's own menu action: asked for through its core. Erasing
            // is still NEO's question to ask — it shows its own dialog first.
            if let action = intent.shellAction { monitor?.neoShell(action) }
        case .wakeWord, .wellbeingCheckins:
            // The core's own setting: asked of the core, which answers
            // everyone with where the switch now stands.
            if let setting = intent.setting { monitor?.neoSet(setting) }
        }
    }

    /// Opens NEO's chat: the panel takes the island from Settings, with the
    /// keyboard, exactly as a click on the island does. Without NEO's page
    /// there is no panel here, and NEO.app shows its own window instead.
    private func openNeoChat() {
        guard hasNeoUI else {
            monitor?.neoShell(.show)
            return
        }
        let now = Date()
        neoPanel.show(at: now)
        applyNeoPanel()
        neoEngageKeyboard()
        scheduleNeoWake(neoNextWake(at: now))
    }

    /// Launches NEO.app, quietly: it is a menu-bar app, and Settings stays in
    /// front. The listener finds its core on its own once it is up.
    private func startNeoApp() {
        let url = URL(fileURLWithPath: NeoSettingsModel.appPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            log("neo: \(url.path) is not there")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async { self?.log("neo: could not start NEO.app: \(error.localizedDescription)") }
        }
    }
}
