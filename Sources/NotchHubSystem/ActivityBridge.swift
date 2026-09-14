import Foundation
import NotchHubCore

/// What the island should do with one system event.
///
/// The bridge decides not only WHICH activity an event becomes but HOW it
/// reaches the queue. That distinction is what keeps the island honest: a
/// volume change must briefly surface over a playing song and hand it back,
/// a timer tick must update the running stopwatch rather than stack a new one,
/// and anything that is merely "currently true" (the weather, a coding agent at
/// work) must never occupy the island at all.
public enum IslandInstruction: Equatable {
    /// Push a persistent activity (a song, a live call, a low-battery
    /// warning). It holds the island until it is replaced or removed.
    case present(Activity)
    /// Take the island immediately, regardless of priority, for the
    /// activity's `autoDismiss` lifetime, then hand it back.
    case presentTransient(Activity)
    /// Update the matching in-flight activity (same kind and title) in place,
    /// or push it when there is none.
    case upsert(Activity)
    /// Drop every activity of a kind.
    case remove(ActivityKind)
    /// No queue change: the event updated state the app keeps for the wings
    /// or a panel, so the island only needs to re-render.
    case refresh
}

/// Translates neutral `SystemEvent`s into island instructions.
///
/// This is the ONLY bridge between the system layer and the presentation layer.
/// Everything above this line speaks `Activity`; everything below speaks
/// `SystemEvent`. Swapping a listener or adding a source never touches the UI,
/// and restyling the island never touches the system code.
public enum ActivityBridge {

    /// The level at which `BatteryListener` warns; any reading above it (or
    /// plugging in) clears the warning.
    public static let lowBatteryThreshold = 10

    /// The instructions for one event, applied in order. Empty for events with
    /// no island consequence at all (sleep/wake).
    public static func instructions(for event: SystemEvent) -> [IslandInstruction] {
        switch event.payload {
        case let .battery(percent, charging, chargingChanged):
            var result: [IslandInstruction] = []
            if charging || percent > lowBatteryThreshold {
                // The warning is persistent, so something has to clear it.
                result.append(.remove(.lowBattery))
            }
            // A percentage ticking down is wing/dashboard status, not news:
            // announcing every 1% kept the battery popping up all day.
            result.append(chargingChanged
                ? .presentTransient(.battery(percent: percent, charging: charging))
                : .refresh)
            return result

        case let .lowBattery(percent):
            return [.present(.lowBattery(percent: percent))]

        case let .volume(level):
            return [.presentTransient(.volume(level))]

        case let .brightness(level):
            return [.presentTransient(.brightness(level))]

        case let .nowPlaying(title, artist, isPlaying, artwork, source):
            return [.present(.music(title: title, artist: artist, isPlaying: isPlaying, artwork: artwork, source: source))]

        case .nowPlayingStopped:
            return [.remove(.music)]

        case let .downloadStarted(name):
            return [.upsert(Activity(
                kind: .download,
                title: name,
                subtitle: "Downloading",
                symbol: "arrow.down.circle.fill"
            ))]

        case let .downloadProgress(name, progress, bytes):
            if let progress {
                return [.upsert(.download(name: name, progress: progress))]
            }
            return [.upsert(.download(name: name, bytesSoFar: bytes))]

        case let .downloadFinished(name):
            return [.upsert(.downloadFinished(name: name))]

        case let .timerTick(elapsed):
            return [.upsert(.timer(elapsed: elapsed))]

        case .timerFinished:
            return [.remove(.timer)]

        case let .focusTick(remaining):
            // The readout counts down: whole seconds left, so it opens on 25:00.
            return [.upsert(.timer(elapsed: remaining.rounded(.up), label: "Focus"))]
        case .focusFinished:
            return [.remove(.timer)]

        case let .screenRecording(active):
            guard active else { return [.remove(.recording)] }
            return [.present(Activity(
                kind: .recording,
                title: "Recording",
                subtitle: "Screen capture active",
                symbol: "record.circle"
            ))]

        case .network:
            // Path changes (VPNs, re-association) fire often and duplicate the
            // Wi-Fi join `DeviceListener` already announces: status only.
            return [.refresh]

        case let .bluetoothDevice(connected, name):
            // AirPods get their own surface — they are the common case on a
            // MacBook. Everything else is a generic Bluetooth connection.
            if name.localizedCaseInsensitiveContains("airpods") {
                return [.presentTransient(.airpods(connected: connected, name: name))]
            }
            return [.presentTransient(Activity(
                kind: .bluetooth,
                title: connected ? "Connected" : "Disconnected",
                subtitle: name,
                symbol: "dot.radiowaves.left.and.right"
            ))]

        case let .meetingStarted(meeting), let .meetingUpdated(meeting):
            // Upsert, so a call's surface keeps one identity for its lifetime.
            return [.upsert(.meeting(meeting))]

        case .meetingEnded:
            return [.remove(.meeting)]

        case let .focus(active, name):
            guard active else { return [.remove(.focus)] }
            // Announced briefly; the wings carry it while it stays on. A
            // persistent activity would keep the island out of idle all day.
            return [.presentTransient(Activity(
                kind: .focus,
                title: name ?? "Focus",
                subtitle: "On",
                symbol: "moon.fill",
                autoDismiss: 2.4
            ))]

        case let .wifi(ssid, connected):
            guard let ssid, connected else { return [.refresh] }
            return [.presentTransient(Activity(kind: .wifi, title: ssid, subtitle: "Connected", symbol: "wifi"))]

        case let .calendarStarting(title, inMinutes):
            let when = inMinutes <= 0 ? "Starting now" : "In \(inMinutes) min"
            return [.presentTransient(Activity(
                kind: .calendar,
                title: title,
                subtitle: when,
                symbol: "calendar",
                autoDismiss: 8
            ))]

        case let .notification(_, title, body):
            return [.presentTransient(.notification(title: title, body: body))]

        case let .codingAgent(running, agent):
            // A running agent is wing status — agents run for hours. Only the
            // moment it finishes is worth taking the island for.
            return running ? [.refresh] : [.presentTransient(.codingAgentFinished(agent))]

        // Panel and wing state the app keeps itself — the Tray, dictation, the
        // frontmost app, privacy dots, the weather, the next-event readout.
        case .clipboardCaptured, .dictation, .frontmostApp, .appContext, .privacy, .weather, .calendarNext:
            return [.refresh]

        case .didWake, .willSleep:
            return []
        }
    }

    /// The activity an event surfaces, if any — the first one its
    /// instructions present or update.
    public static func activity(for event: SystemEvent) -> Activity? {
        for instruction in instructions(for: event) {
            switch instruction {
            case let .present(activity), let .presentTransient(activity), let .upsert(activity):
                return activity
            case .remove, .refresh:
                continue
            }
        }
        return nil
    }
}
