import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// Launch flags, demo sequences, and the inspection hooks used to verify one
/// surface on screen at a time.
extension NotchHubApp {

    /// A script for `--teleprompter` with no `--script` of its own.
    static let sampleScript = """
    Good morning everyone, and thanks for making the time.

    I want to walk through three things today: where the release stands, what \
    changed since last week, and what we still need a decision on.

    First, the release. We closed the last two blocking bugs on Tuesday, and \
    the build has been green since.

    Second, what changed. The hover strip now lights the control under your \
    cursor, a closed media tab clears the island at once, and the pet's panel \
    opens centred on the notch.

    Third, the decision. We can ship on Thursday, or hold a week and take the \
    camera work with it. I would like a view before we finish today.
    """

    /// Reads the launch flags and starts the matching mode. A normal launch
    /// only starts the monitor: the island stays invisible until something
    /// real happens.
    func startLaunchMode() {
        let arguments = CommandLine.arguments

        // `--no-ghost`: make the island visible to screen capture for this run
        // only, so an inspection screenshot can actually see it. In memory and
        // deliberately NOT saved — it must never change what the user chose.
        if arguments.contains("--no-ghost") {
            featureSettings.setEnabled(.ghostMode, enabled: false)
            log("ghost: disabled for this run only (--no-ghost)")
        }

        // `--neo-capturable`: leave the window visible to screen capture in
        // EVERY shape (Ghost Mode and the always-private surfaces included),
        // so a `screencapture` of the notch strip shows NEO's lane and panel
        // during a debug run. In memory only, never saved.
        if arguments.contains("--neo-capturable") {
            capturableForDebug = true
            log("ghost: window left capturable for this run only (--neo-capturable)")
        }
        installNeoSnapshotSignal()

        if let index = arguments.firstIndex(of: "--art"), index + 1 < arguments.count {
            let path = arguments[index + 1]
            demoArtwork = FileManager.default.contents(atPath: path)
            log("art: loaded \(demoArtwork?.count ?? 0) bytes from \(path)")
        }

        if let index = arguments.firstIndex(of: "--activity"), index + 1 < arguments.count {
            // Presents ONE named activity and holds it, so a single surface can
            // be inspected on screen in isolation.
            let name = arguments[index + 1]
            startMonitor()
            after(0.6) { $0.presentNamedActivity(name) }
        } else if arguments.contains("--demo") {
            // The scripted sequence stays clean: no live listeners.
            runDemoSequence()
        } else if arguments.contains("--hold") {
            present(.music(title: "Midnight City", artist: "M83"))
        } else if arguments.contains("--states") {
            runStatesSequence()
        } else if arguments.contains("--tray") {
            startMonitor()
            after(0.6) { $0.toggleTray() }
        } else if arguments.contains("--settings") {
            startMonitor()
            after(0.6) { $0.toggleSettings() }
        } else if let index = arguments.firstIndex(of: "--filedrop"), index + 1 < arguments.count {
            // Simulates a file drop: automation cannot synthesise a real AppKit
            // drag session, so this drives the app's own drop handling.
            let path = arguments[index + 1]
            startMonitor()
            after(0.6) { app in
                app.fileDraggedIn()
                app.fileDropped([URL(fileURLWithPath: path)])
            }
        } else if arguments.contains("--wings") {
            // Opens the sideways wings and HOLDS them for inspection. `--music`
            // also seeds a playing track so the visualizer can be inspected.
            startMonitor()
            holdWings = true
            if arguments.contains("--music") {
                musicTitle = "Midnight City"
            }
            after(0.6) { app in
                app.queue.removeAll()
                app.machine.setActivity(nil)
                app.machine.isHovering = true
                app.machine.send(.hoverEntered)
                app.refreshIsland()
                app.log("wings: opened for inspection")
            }
        } else if arguments.contains("--timer") {
            startMonitor()
            after(0.6) { $0.toggleTimer() }
        } else if arguments.contains("--teleprompter") {
            // Opens the prompter for inspection. `--script PATH` loads a file;
            // otherwise a sample is seeded so it has something to scroll.
            startMonitor()
            let path = arguments.firstIndex(of: "--script").flatMap { index in
                index + 1 < arguments.count ? arguments[index + 1] : nil
            }
            let play = arguments.contains("--play")
            after(0.6) { app in
                if let path {
                    app.teleprompter.load(Self.readScript(at: URL(fileURLWithPath: path)) ?? "")
                } else {
                    app.teleprompter.load(Self.sampleScript)
                }
                app.toggleTeleprompter()
                if play { app.startTeleprompter() }
            }
        } else if arguments.contains("--camera-cycle") {
            // Opens the camera, then closes it again, printing the phase at each
            // step. The point is the CLOSE: macOS's own green in-use indicator
            // must go out, which is the only real proof the session was released
            // rather than merely hidden.
            startMonitor()
            after(0.6) { app in
                app.toggleCamera()
                app.log("camera-cycle: opened")
            }
            after(4.0) { app in
                app.log("camera-cycle: before close — phase=\(app.cameraState.phase) running=\(app.camera.isRunning)")
                app.closeCamera()
            }
            after(7.0) { app in
                app.log("camera-cycle: after close — phase=\(app.cameraState.phase) running=\(app.camera.isRunning) panel=\(app.panel == .none ? "none" : "open")")
            }
        } else if arguments.contains("--camera") {
            startMonitor()
            after(0.6) { $0.toggleCamera() }
        } else if arguments.contains("--neo-timer-demo") {
            // NEO's timers counting down on the real island, scripted — NEO's
            // own listener is never started, so no core is asked anything.
            featureSettings.setEnabled(.neo, enabled: false)
            startMonitor()
            featureSettings.setEnabled(.neo, enabled: true)
            after(0.6) { $0.runNeoTimerDemo() }
        } else if arguments.contains("--neo-demo") {
            // The pet posing as NEO through a scripted turn, with the live
            // listeners (but not NEO's own) so it can be seen on the real island.
            featureSettings.setEnabled(.neo, enabled: false)
            startMonitor()
            featureSettings.setEnabled(.neo, enabled: true)
            after(0.6) { $0.runNeoDemo() }
        } else {
            // Once launch has finished, so the app is up and answering the
            // system before any listener reaches for files, scripts or
            // permissions.
            after(0.2) { $0.startMonitor() }
            // Only a normal launch manages the Mac's sleep (and puts right a
            // SleepDisabled a crash left behind).
            startLidAwake()
        }
    }

    /// Runs `action` on the main actor after `seconds`.
    func after(_ seconds: Double, _ action: @escaping @MainActor (NotchHubApp) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self else { return }
            action(self)
        }
    }

    /// `--demo`: a persistent song holds the island, and transient system
    /// events briefly take it over before handing it back.
    func runDemoSequence() {
        after(0.2) { $0.present(.music(title: "Midnight City", artist: "M83")) }
        let transients: [(TimeInterval, Activity)] = [
            (3.0, .volume(0.62)),
            (5.5, .brightness(0.75)),
            (8.0, .battery(percent: 82, charging: true)),
            (10.5, .airpods(connected: true)),
            (13.0, Activity.download(name: "DesignSpec.pdf", progress: 0.35).withAutoDismiss(2.4)),
            (16.0, .notification(title: "Calendar", body: "Design review in 10 min")),
        ]
        for (delay, activity) in transients {
            after(delay) { $0.presentTransient(activity) }
        }
    }

    /// `--states`: walks the island through every presentation state through
    /// the same state machine the live interactions use.
    func runStatesSequence() {
        after(0.5) { app in
            app.present(.music(title: "Midnight City", artist: "M83"))
            app.log("state: idle → compact")
        }
        after(4.0) { app in
            app.machine.send(.hoverEntered)
            app.refreshIsland()
            app.log("state: compact → expanded (hover)")
        }
        after(8.5) { app in
            app.machine.send(.clicked)
            app.refreshIsland()
            app.log("state: expanded → dashboard (click)")
        }
        after(13.0) { app in
            app.machine.send(.dismissed)
            app.refreshIsland()
            app.log("state: dashboard → compact (collapse)")
        }
        after(16.5) { app in
            app.queue.removeAll()
            app.machine.setActivity(nil)
            app.machine.send(.dismissed)
            app.refreshIsland()
            app.log("state: compact → idle")
        }
    }

    /// `--activity <name>`: presents ONE named activity and holds it (600 s) so
    /// a single surface can be verified on screen in isolation.
    func presentNamedActivity(_ name: String) {
        let kinds: [String: ActivityKind] = [
            "music": .music, "volume": .volume, "brightness": .brightness,
            "battery": .battery, "lowbattery": .lowBattery, "low-battery": .lowBattery,
            "timer": .timer, "download": .download, "notification": .notification,
            "airpods": .airpods, "bluetooth": .bluetooth, "recording": .recording,
            "microphone": .microphone, "mic": .microphone, "camera": .camera,
            "calendar": .calendar, "focus": .focus, "dnd": .dnd, "wifi": .wifi,
            "clipboard": .clipboard,
        ]
        var held = makeDemoActivity(kinds[name] ?? .music).withAutoDismiss(600)
        // `--art <path>` seeds real artwork for the now-playing surface.
        if let demoArtwork { held.artwork = demoArtwork }
        present(held)
        log("activity: presented \(name) artwork=\(demoArtwork?.count ?? 0) bytes")
    }

    /// Builds a representative `Activity` for a demo kind.
    func makeDemoActivity(_ kind: ActivityKind) -> Activity {
        switch kind {
        case .music: return .music(title: "Midnight City", artist: "M83")
        case .volume: return .volume(0.62)
        case .brightness: return .brightness(0.75)
        case .battery: return .battery(percent: 82, charging: true)
        case .lowBattery: return .lowBattery(percent: 12)
        case .timer:
            demoStart = Date()
            return .timer(elapsed: 0)
        case .download: return .download(name: "DesignSpec.pdf", progress: 0.35)
        case .notification: return .notification(title: "Calendar", body: "Design review in 10 min")
        case .airpods: return .airpods(connected: true)
        case .bluetooth: return Activity(kind: .bluetooth, title: "Bluetooth", subtitle: "On", symbol: "dot.radiowaves.left.and.right")
        case .recording: return Activity(kind: .recording, title: "Recording", subtitle: "Screen", symbol: "record.circle")
        case .microphone: return Activity(kind: .microphone, title: "Microphone", subtitle: "In use", symbol: "mic.fill")
        case .camera: return Activity(kind: .camera, title: "Camera", subtitle: "In use", symbol: "video.fill")
        case .calendar: return Activity(kind: .calendar, title: "Calendar", subtitle: "Design review · 10 min", symbol: "calendar")
        case .focus: return Activity(kind: .focus, title: "Focus", subtitle: "Until 5 PM", symbol: "moon.fill")
        case .dnd: return Activity(kind: .dnd, title: "Do Not Disturb", subtitle: "On", symbol: "moon.zzz.fill")
        case .wifi: return Activity(kind: .wifi, title: "Wi-Fi", subtitle: "Connected", symbol: "wifi")
        case .clipboard: return Activity(kind: .clipboard, title: "Clipboard", subtitle: "Copied", symbol: "doc.on.clipboard")
        case .songRecognition: return Activity(kind: .songRecognition, title: "Listening for a song", subtitle: "Listening · 0:04", progress: 0.4)
        default: return Activity(kind: kind, title: kind.rawValue, symbol: kind.defaultSymbol)
        }
    }

    /// Returns the island to its invisible idle state.
    func returnToIdle() {
        queue.removeAll()
        // NEO's countdown went with everything else, and stays away until
        // NEO's timers change — rather than coming straight back on the next tick.
        neoTimerSurface.dismiss()
        machine.setActivity(nil)
        machine.send(.dismissed)
        renderIsland(stackCount: 0)
    }
}
