import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// The surfaces that temporarily replace the queue-driven island — the Tray,
/// settings, dictation, file drop — plus the global hotkeys that open them.
extension NotchHubApp {

    /// The surface that replaces the queue-driven content, when one is showing.
    func panelContent() -> AnyView? {
        switch panel {
        case .tray:
            return AnyView(
                TrayView(
                    store: trayStore,
                    search: Binding(
                        get: { [weak self] in self?.traySearch ?? "" },
                        set: { [weak self] in
                            self?.traySearch = $0
                            self?.refreshPanel()
                        }
                    ),
                    filter: Binding(
                        get: { [weak self] in self?.trayFilter ?? .all },
                        set: { [weak self] in
                            self?.trayFilter = $0
                            self?.refreshPanel()
                        }
                    ),
                    onSelect: { [weak self] clip in self?.copyToPasteboard(clip) },
                    onPin: { [weak self] clip in self?.togglePin(clip) },
                    onDelete: { [weak self] clip in self?.deleteClip(clip) }
                )
            )

        case .dictation:
            return AnyView(
                DictationView(session: dictationSession) { [weak self] in
                    self?.dictation.finish()
                }
            )

        case .settings:
            return AnyView(
                SettingsView(
                    settings: Binding(
                        get: { [weak self] in self?.settingsModel ?? IslandSettings() },
                        set: { [weak self] model in
                            guard let self else { return }
                            // Redraw first, so the tile responds on the tap;
                            // the (deferred) system work comes after.
                            self.settingsModel = model
                            self.refreshPanel()
                            self.applySettings(model)
                        }
                    ),
                    onChange: {},
                    onClose: { [weak self] in self?.closeSettings() }
                )
            )

        case .fileDrop:
            return AnyView(
                FileDropView(
                    fileName: fileDropURLs.first?.lastPathComponent ?? "",
                    phase: fileDropPhase,
                    onDestination: { [weak self] destination in
                        self?.share(to: destination)
                    }
                )
            )

        case .pet:
            return AnyView(PetPanelView(
                presentation: petBrain.presentation,
                side: petPanelAnchor?.side,
                look: petSettings.look,
                hat: petSettings.hat.hat(on: Date(), holiday: todaysHoliday()),
                hatChoice: petSettings.hat,
                isFocusing: timerService.isCountingDown,
                greeting: todaysHoliday()?.greeting ?? PetIdentity.hello,
                focusEnabled: featureSettings.isEnabled(.timers) || timerService.isCountingDown,
                contentLeading: petPanelContentLeading()
            ))

        case .none:
            // A click opens the frontmost app's panel, or the dashboard.
            if currentIslandState() == .appPanel, let content = appPanelContent() {
                return content
            }
            if currentIslandState() == .interactive {
                return dashboardContent()
            }
            // With nothing playing and no panel open, the island's resting
            // face is the app you are in — the skin, seen on hover.
            if machine.activity == nil, let skin {
                return AnyView(SkinView(skin: skin))
            }
        }

        // A call's controls, once the island is expanded.
        if let meeting, currentIslandState() == .meeting {
            return AnyView(
                MeetingView(
                    meeting: meeting,
                    onMute: { [weak self] in self?.toggleMeetingMute() },
                    onCamera: { [weak self] in self?.toggleMeetingCamera() },
                    onLeave: { [weak self] in self?.leaveMeeting() }
                )
            )
        }

        return nil
    }

    func refreshPanel() {
        renderIsland()
    }

    /// Where the pet panel's content starts, from the panel's left edge — laid
    /// out by `PetPanelLayout`, which keeps the big pet clear of the notch.
    func petPanelContentLeading() -> CGFloat {
        var content = IslandContentSize.default
        content.panelAnchor = petPanelAnchor
        let frame = window.localFrame(for: .skin, content: content)
        let notch = window.localFrame(for: .idle, content: .default)
        return PetPanelLayout.contentMinX(in: frame, side: petPanelAnchor?.side, notch: notch) - frame.minX
    }

    // MARK: - Tray

    /// Puts a clip back on the pasteboard so it can be pasted anywhere.
    func copyToPasteboard(_ clip: TrayClip) {
        log("tray: selected \(clip.kind)")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch clip.kind {
        case .image, .screenshot:
            if let path = clip.imagePath, let image = NSImage(contentsOfFile: path) {
                pasteboard.writeObjects([image])
            }
        case .file:
            let urls = clip.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty { pasteboard.writeObjects(urls) }
        default:
            if let text = clip.text { pasteboard.setString(text, forType: .string) }
        }
        trayStore.moveToFront(id: clip.id)
        TrayPersistence.save(trayStore)
        closePanel()
    }

    func togglePin(_ clip: TrayClip) {
        trayStore.setPinned(id: clip.id, pinned: !clip.pinned)
        TrayPersistence.save(trayStore)
        refreshPanel()
    }

    func deleteClip(_ clip: TrayClip) {
        trayStore.remove(id: clip.id)
        TrayPersistence.save(trayStore)
        refreshPanel()
    }

    /// Opens the Tray, or closes it if it is already showing.
    func toggleTray() {
        if panel == .tray {
            closeTray()
            return
        }
        panel = .tray
        machine.send(.activityStarted)
        // The Tray's rows are real buttons (copy, pin, delete), so it needs
        // the same key/click handling the settings panel gets.
        window.needsInteraction = true
        log("tray: open")
        refreshPanel()
    }

    /// Dismisses the Tray and hands focus back to the user's app.
    func closeTray() {
        guard panel == .tray else { return }
        closePanel()
        log("tray: closed")
    }

    // MARK: - Timer & dictation

    /// Starts or stops the island's own stopwatch, gated on the timers setting.
    func toggleTimer() {
        guard featureSettings.isEnabled(.timers) else {
            log("timer: disabled by settings")
            return
        }
        // Only the stopwatch toggles here; it replaces a focus session instead of
        // ending it and starting nothing.
        if timerService.isStopwatchRunning {
            timerService.stopTimer()
            log("timer: stopped")
        } else {
            demoStart = nil
            timerService.startTimer()
            log("timer: started")
        }
    }

    /// Starts or stops dictation, gated on the dictation setting.
    func toggleDictation() {
        if panel == .dictation {
            dictation.finish()
            return
        }
        guard featureSettings.isEnabled(.dictation) else {
            log("dictation: disabled by settings")
            return
        }
        dictation.begin()
    }

    // MARK: - Settings

    /// Opens the settings panel, or closes it if it is already showing.
    func toggleSettings() {
        if panel == .settings {
            closeSettings()
            return
        }
        panel = .settings
        machine.send(.activityStarted)
        // The settings panel holds real controls, so the window must be able
        // to take key status to receive their clicks.
        window.needsInteraction = true
        log("settings: open")
        refreshPanel()
    }

    /// Dismisses the settings panel and hands focus back to the user's app.
    func closeSettings() {
        guard panel == .settings else { return }
        closePanel()
        log("settings: closed")
    }

    /// Dismisses whichever interactive panel is open.
    func dismissInteractivePanel() {
        switch panel {
        case .settings: closeSettings()
        case .tray: closeTray()
        case .dictation: dictation.finish()
        case .fileDrop: closeFileDrop()
        case .pet: closePetPanel()
        case .none: break
        }
    }

    func closePanel() {
        panel = .none
        window.needsInteraction = false
        renderIsland()
    }

    // MARK: - File sharing

    /// A file entered the island's drop zone: reveal the drop surface.
    func fileDraggedIn() {
        guard featureSettings.isEnabled(.fileSharing) else { return }
        panel = .fileDrop
        fileDropPhase = .hovering
        window.needsInteraction = true
        machine.send(.activityStarted)
        refreshPanel()
    }

    /// The file left without being dropped: hide the drop surface.
    func fileDraggedOut() {
        guard panel == .fileDrop else { return }
        closeFileDrop()
    }

    /// A file was dropped: offer the share destinations.
    func fileDropped(_ urls: [URL]) {
        guard panel == .fileDrop, !urls.isEmpty else { return }
        fileDropURLs = urls
        fileDropPhase = .dropped
        refreshPanel()
    }

    /// Closes the drop surface and hands focus back.
    func closeFileDrop() {
        guard panel == .fileDrop else { return }
        fileDropURLs = []
        fileDropPhase = .idle
        closePanel()
    }

    /// Performs the chosen share action. Only destinations that genuinely work
    /// are offered, so each one maps to a real macOS service.
    func share(to destination: String) {
        let urls = fileDropURLs
        switch destination {
        case "AirDrop":
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        case "Clipboard":
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
        default:
            break
        }
        log("fileShare: \(destination) for \(urls.count) file(s)")
        closeFileDrop()
    }

    // MARK: - Hotkeys

    /// ⌥⌘V opens the Tray; ⌥⌘M dictates; ⌥⌘, opens settings; ⌥⌘T toggles the
    /// timer. Carbon hotkeys need no permission.
    func registerHotKeys() {
        hotKeys.append(contentsOf: [
            HotKey(keyCode: HotKey.Key.v, modifiers: [.option, .command]) { [weak self] in
                self?.toggleTray()
            },
            HotKey(keyCode: HotKey.Key.m, modifiers: [.option, .command]) { [weak self] in
                self?.toggleDictation()
            },
            HotKey(keyCode: HotKey.Key.comma, modifiers: [.option, .command]) { [weak self] in
                self?.toggleSettings()
            },
            HotKey(keyCode: HotKey.Key.t, modifiers: [.option, .command]) { [weak self] in
                self?.toggleTimer()
            },
        ].compactMap { $0 })
        log("hotkeys: \(hotKeys.count)/4 registered")
    }
}
