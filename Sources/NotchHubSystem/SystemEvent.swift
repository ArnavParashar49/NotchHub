import Foundation
import NotchHubCore

/// A neutral fact about the system, emitted by a listener.
///
/// Listeners know nothing about the island, activities, or presentation — they
/// only observe the system and report what changed. `ActivityBridge` is the
/// only place that decides how an event should look when it reaches the UI.
public struct SystemEvent: Equatable {

    /// Where the event came from. One listener per source.
    public enum Source: String, CaseIterable {
        case battery
        case volume
        case brightness
        case nowPlaying
        case downloads
        case timer
        case system
        case screenCapture
        case network
        case bluetooth
        /// A new clipboard entry landed in the Tray.
        case clipboard
        /// Camera / microphone in use.
        case privacy
        /// The frontmost app changed.
        case frontmostApp
        /// A call started, changed, or ended.
        case meeting
        /// Do Not Disturb / Focus toggled.
        case focus
        /// Wi-Fi joined or left.
        case wifi
        /// The next calendar event is close, or a new one was scheduled.
        case calendar
        /// A notification banner appeared.
        case notification
        /// A coding agent (Claude Code, Codex, …) changed state.
        case codingAgent
        /// Current weather for the configured city.
        case weather
        /// NEO's core: its state and transcript.
        case neo
    }

    /// What happened.
    public enum Payload: Equatable {
        /// `chargingChanged` is true only when the charger was just connected or
        /// disconnected (never for the first reading).
        case battery(percent: Int, charging: Bool, chargingChanged: Bool)
        case lowBattery(percent: Int)
        case volume(level: Double)
        case brightness(level: Double)
        /// `source` is the bundle identifier of the player, when known.
        case nowPlaying(title: String, artist: String, isPlaying: Bool, artwork: Data?, source: String?)
        case nowPlayingStopped
        case downloadStarted(name: String)
        /// `progress` is 0…1 when the total size is known, `nil` when only the
        /// bytes received so far can be observed.
        case downloadProgress(name: String, progress: Double?, bytes: Int64)
        case downloadFinished(name: String)
        case timerTick(elapsed: TimeInterval)
        case timerFinished
        /// A focus countdown ticked: the time left.
        case focusTick(remaining: TimeInterval)
        /// A focus countdown ended — it ran out (`completed`) or was stopped.
        case focusFinished(completed: Bool)
        case screenRecording(active: Bool)
        case network(name: String)
        case bluetoothDevice(connected: Bool, name: String)
        case didWake
        case willSleep

        // MARK: - Tray

        /// A new entry was copied. The app files it into the Tray.
        case clipboardCaptured(TrayClip)

        // MARK: - Privacy

        /// Whether the camera and microphone are currently in use.
        case privacy(camera: Bool, microphone: Bool)

        // MARK: - App skins

        /// The frontmost app changed. `nil` when it is not worth skinning.
        case frontmostApp(AppSkin?)
        /// Details about the frontmost app — its page, agent session, or window
        /// title. `nil` when there are none (or none yet for a new app).
        case appContext(AppContextSnapshot?)

        // MARK: - Meetings

        case meetingStarted(Meeting)
        case meetingUpdated(Meeting)
        case meetingEnded

        // MARK: - Focus & network

        case focus(active: Bool, name: String?)
        case wifi(ssid: String?, connected: Bool)

        // MARK: - Calendar

        /// The next event, refreshed periodically. `nil` when the day is clear.
        case calendarNext(UpcomingEvent?)
        /// An event is about to start — worth surfacing.
        case calendarStarting(title: String, inMinutes: Int)

        // MARK: - Notifications, coding agents & weather

        /// A notification banner was delivered by the given app.
        case notification(app: String, title: String, body: String)
        /// A coding agent started (`running`) or stopped running.
        case codingAgent(running: Bool, agent: String)
        /// Current conditions for the configured city.
        case weather(temperature: Double, condition: String, symbol: String)

        // MARK: - NEO

        /// A fact from NEO's core: connected or not, its state, a transcript
        /// line, a note or an error. Never an activity.
        case neo(NeoFact)
        /// What NEO.app's shell reported through the core (its permissions,
        /// Open at Login, its version): for the NEO section of Settings.
        case neoShell(NeoShellStatus)
    }

    public let source: Source
    public let payload: Payload
    public let date: Date

    public init(source: Source, payload: Payload, date: Date = Date()) {
        self.source = source
        self.payload = payload
        self.date = date
    }
}
