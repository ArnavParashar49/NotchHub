import AppKit
import NotchHubCore
import SwiftUI

/// The dashboard a click on the notch opens.
extension NotchHubApp {

    /// The song on the island, if any.
    var musicActivity: Activity? {
        queue.all.first { $0.kind == .music }
    }

    /// What the dashboard's right column is about right now.
    func dashboardFocus() -> DashboardFocus {
        DashboardFocus.choose(event: nextEvent, now: Date(), hasNowPlaying: musicActivity != nil)
    }

    func dashboardContent() -> AnyView {
        let music = musicActivity
        return AnyView(
            DashboardView(
                notchInset: window.notchHeight,
                focus: dashboardFocus(),
                nextEvent: nextEvent,
                nowPlayingTitle: music?.title,
                nowPlayingArtist: music?.subtitle,
                weatherSymbol: weatherActivity?.resolvedSymbol,
                weatherLabel: weatherActivity?.subtitle,
                batteryPercent: batteryPercent,
                isCharging: isCharging,
                focusMode: focusMode,
                isMicActive: isMicActive,
                isCameraActive: isCameraActive,
                timerElapsed: timerService.isStopwatchRunning ? timerElapsed : nil,
                timerEnabled: featureSettings.isEnabled(.timers),
                isDictating: dictationSession.isActive,
                dictationEnabled: featureSettings.isEnabled(.dictation),
                trayCount: trayStore.clips.count
            )
        )
    }

    /// Handles a click on one of the dashboard's controls. Returns whether a
    /// control was hit; a miss falls through to the island click, which closes
    /// the dashboard.
    func dashboardControlHit(at point: NSPoint) -> Bool {
        guard currentIslandState() == .interactive else { return false }
        let frame = window.localFrame(for: .interactive, content: islandModel.contentSize)
        guard let action = DashboardLayout.action(
            at: point,
            in: frame,
            notchInset: window.notchHeight,
            focus: dashboardFocus()
        ) else {
            return false
        }
        performDashboardAction(action)
        return true
    }

    func performDashboardAction(_ action: DashboardAction) {
        log("dashboard: \(action.rawValue)")
        switch action {
        case .timer:
            // Stays open: the chip turns into the running readout.
            toggleTimer()
            renderIsland()
            return
        case .settings:
            closeDashboard()
            toggleSettings()
        case .tray:
            closeDashboard()
            toggleTray()
        case .dictation:
            closeDashboard()
            toggleDictation()
        case .join:
            closeDashboard()
            if let url = nextEvent?.joinURL {
                NSWorkspace.shared.open(url)
            }
        case .openPlayer:
            closeDashboard()
            if let music = musicActivity {
                openSourceApp(for: music)
            }
        }
        renderIsland()
    }

    /// Steps the machine out of the dashboard. The caller renders once, so a
    /// panel opening from the dashboard is one motion, not two.
    func closeDashboard() {
        guard machine.presentation == .interactive else { return }
        machine.send(.dismissed)
    }
}
