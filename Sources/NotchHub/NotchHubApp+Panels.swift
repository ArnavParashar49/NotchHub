import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// The surfaces that temporarily replace the queue-driven island — the Tray,
/// settings, the file drop — plus the global hotkeys that open them.
extension NotchHubApp {

    /// The surface that replaces the queue-driven content, when one is showing.
    func panelContent() -> AnyView? {
        // NEO's Allow / Cancel are drawn over whatever the island holds.
        if currentIslandState() == .neoConfirm, let card = neoConfirm.card {
            return neoConfirmContent(card)
        }
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
                    onClose: { [weak self] in self?.closeSettings() },
                    neo: neoSettings,
                    onNeo: { [weak self] in self?.neoSettingsIntent($0) },
                    lid: lidSettings,
                    lidApps: lidAppChoices(),
                    onLid: { [weak self] in self?.lidIntent($0) },
                    page: settingsStartPage
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
                look: petSettings.look,
                hat: petSettings.hat.hat(on: Date(), holiday: todaysHoliday()),
                hatChoice: petSettings.hat,
                palette: petSettings.usesCustomFur ? petPalette : nil,
                accessory: petSettings.accessory.accessory,
                name: petSettings.displayName,
                isFocusing: timerService.isCountingDown,
                greeting: todaysHoliday()?.greeting ?? PetIdentity.hello(name: petSettings.displayName),
                focusEnabled: featureSettings.isEnabled(.timers) || timerService.isCountingDown,
                contentLeading: petPanelContentLeading()
            ))

        case .teleprompter:
            return teleprompterContent()

        case .camera:
            return cameraContent()

        case .neoCamera:
            return neoCameraContent()

        case .neo:
            return neoPanelContent()

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

    // MARK: - Panel ownership

    /// Takes the island for `panel`, releasing whatever held it first.
    ///
    /// Only ONE panel can be on the island, and one of them holds hardware: the
    /// camera has a live capture session. Setting `panel` directly — which every
    /// opener used to do — swapped the surface and left that hardware running
    /// with nothing on screen owning it. Every opener goes through here instead,
    /// so taking the island always releases what it replaces.
    func takePanel(_ panel: Panel) {
        releaseCurrentPanel(except: panel)
        if self.panel == .neo, panel != .neo {
            // Another surface takes the island from NEO's panel: the panel's
            // model must know it is closed, or it would take the island back.
            neoPanel.close(at: Date())
        }
        self.panel = panel
        machine.send(.activityStarted)
    }

    /// Lets go of whatever the current panel owns. Does not change `panel`
    /// itself — the caller is either replacing it or closing it.
    func releaseCurrentPanel(except keep: Panel? = nil) {
        guard panel != keep else { return }
        switch panel {
        case .camera:
            camera.close()
        case .neoCamera:
            // The ×, or another panel taking the island: stop that session
            // (by name, so a late stop never ends a newer one), and remember
            // it so nothing NEO still says about it — its `off`, its close —
            // brings the panel back (`NeoCameraSurface`). After NEO's own
            // close there is no session left to stop.
            if let sid = neoCameraSurface.release() {
                monitor?.neoCameraStop(sid: sid)
            }
            monitor?.neoCameraVisible(false)
            clearNeoCameraStream()
        case .teleprompter:
            teleprompter.pause()
        case .fileDrop:
            fileDropURLs = []
            fileDropPhase = .idle
        case .neo:
            // The web view is kept: the chat keeps its place between openings.
            break
        case .tray, .settings, .pet, .none:
            break
        }
    }

    /// Where the pet panel's content starts, from the panel's left edge — taken
    /// from `PetPanelLayout`, so the view draws exactly where the window
    /// hit-tests.
    func petPanelContentLeading() -> CGFloat {
        let frame = window.localFrame(for: .skin, content: .default)
        return PetPanelLayout.contentMinX(in: frame) - frame.minX
    }

    // MARK: - Tray

    /// Puts a clip back on the pasteboard so it can be pasted anywhere.
    func copyToPasteboard(_ clip: TrayClip) {
        log("tray: selected \(clip.kind)")
        guard let text = clip.text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
        takePanel(.tray)
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

    // MARK: - Timer

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

    // MARK: - Settings

    /// Opens the settings panel, or closes it if it is already showing.
    func toggleSettings() {
        if panel == .settings {
            closeSettings()
            return
        }
        takePanel(.settings)
        // The settings panel holds real controls, so the window must be able
        // to take key status to receive their clicks.
        window.needsInteraction = true
        log("settings: open")
        // The Lid card shows what `pmset -g` says now, not a memory of it.
        lidAwake?.refresh()
        refreshPanel()
    }

    /// Dismisses the settings panel and hands focus back to the user's app.
    func closeSettings() {
        guard panel == .settings else { return }
        settingsStartPage = .features
        closePanel()
        log("settings: closed")
    }

    /// Dismisses whichever interactive panel is open.
    func dismissInteractivePanel() {
        switch panel {
        case .settings: closeSettings()
        case .tray: closeTray()
        case .fileDrop: closeFileDrop()
        case .pet: closePetPanel()
        case .teleprompter: closeTeleprompter()
        case .camera: closeCamera()
        case .neoCamera: closePanel()
        case .neo: closeNeoPanel()
        case .none: break
        }
    }

    /// Puts the island back, releasing whatever the panel owned.
    func closePanel() {
        releaseCurrentPanel()
        panel = .none
        window.needsInteraction = false
        renderIsland()
    }

    // MARK: - File sharing

    /// A file entered the island's drop zone: reveal the drop surface.
    func fileDraggedIn() {
        guard featureSettings.isEnabled(.fileSharing) else { return }
        takePanel(.fileDrop)
        fileDropPhase = .hovering
        window.needsInteraction = true
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

    /// ⌥⌘V opens the Tray; ⌥⌘, opens settings; ⌥⌘T toggles the timer; ⌥⌘P the
    /// teleprompter; ⌥⌘C the camera; ⌥⌘G Ghost Mode. Carbon hotkeys need no
    /// permission — which matters most for Ghost Mode, the one people reach for
    /// with a call already running.
    func registerHotKeys() {
        hotKeys.append(contentsOf: [
            HotKey(keyCode: HotKey.Key.v, modifiers: [.option, .command]) { [weak self] in
                self?.toggleTray()
            },
            HotKey(keyCode: HotKey.Key.comma, modifiers: [.option, .command]) { [weak self] in
                self?.toggleSettings()
            },
            HotKey(keyCode: HotKey.Key.t, modifiers: [.option, .command]) { [weak self] in
                self?.toggleTimer()
            },
            HotKey(keyCode: HotKey.Key.p, modifiers: [.option, .command]) { [weak self] in
                self?.toggleTeleprompter()
            },
            HotKey(keyCode: HotKey.Key.c, modifiers: [.option, .command]) { [weak self] in
                self?.toggleCamera()
            },
            HotKey(keyCode: HotKey.Key.g, modifiers: [.option, .command]) { [weak self] in
                self?.toggleGhostMode()
            },
        ].compactMap { $0 })
        log("hotkeys: \(hotKeys.count)/6 registered")
    }
}
