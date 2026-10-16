import Foundation
import NotchHubCore

/// Listens to NEO's core over its local websocket and relays what it says.
///
/// NEO (the voice assistant) runs its own core at `ws://127.0.0.1:8765`, which
/// only admits clients that know the token NEO.app keeps in `~/.neo/ws-token`.
/// This listener is a second client beside NEO's own overlay: it reads that
/// one file (nothing else under `~/.neo`), connects with the token, and turns
/// the core's `hello` / `state` / `transcript` / `note` / `error` messages,
/// its cards (`browser_open` / `browser_close`; the camera's `camera_open`,
/// `camera_state`, `camera_close` and the hello's `camera.live`; the song's
/// `song_open`, `song_state`, `song_close`) and its `woke` (NEO summoned by
/// hand) into `NeoFact`s — and what NEO.app's shell reported (the hello's
/// `shell`, and `shell_status`) into a `NeoShellStatus`. A confirmation NEO
/// stages (`confirm`, or the one pending in the `hello`) and its end
/// (`confirm_done`) are facts too: the island's Allow / Cancel. What the core
/// says about its own settings (the hello's `wake_word` and
/// `wellbeing_checkins`, and `settings`) is a `NeoCoreSettings`; what it says
/// about its brains (the hello's `brains`, and `brains`) a `NeoBrainStatus` —
/// whether NEO has a model, and each role's by name: never a key, which the
/// core sends no host and this listener never asks for. NEO's timers
/// are facts for the island's countdown (`NeoTimers`): the ones counting down
/// when NotchHub connects (the hello's `timers`), then each one starting or
/// ending (`activity` events of kind `timer`; any other kind is not ours).
/// Their names are the user's words, kept in memory for the island and never
/// logged; nothing is ever sent back about them. Of the
/// binary frames, only the live camera session's preview (NBF1, kind 3) is
/// read — at most 24 a second, held in memory and never written anywhere.
///
/// The commands it sends, and nothing else, ever:
/// - `camera_view` — `visible:false` on every connection, so the core never
///   streams camera frames to a client that is not showing them, then
///   `visible:true` only while NotchHub's NEO camera panel is on screen and
///   `visible:false` again as it goes (`setCameraVisible(_:)`);
/// - `camera_stop`, naming the session, when the user closes that panel or
///   another one covers it (`stopCamera(sid:)`);
/// - `song_hello` on every connection, so a song card already open when
///   NotchHub connects is shown;
/// - when NotchHub hosts NEO's UI (`hostsUI`), `ui_host notch` on every
///   connection and `ui_host window` as it stops, so NEO.app keeps its own
///   window hidden while the notch shows NEO and brings it back afterwards;
/// - `shell` (`send(_:)`), one of NEO.app's menu actions, when the user asks
///   for it in Settings;
/// - `set` (`send(_:)` with a setting), when the user flips "Listen for
///   'Neo'" or "Gentle check-ins" there — the core takes it from a host;
/// - `confirm` (`send(_:)` with an answer), when the user presses Allow or
///   Cancel under the notch — the very command NEO's own page sends from its
///   card, naming the card's action id.
///
/// It connects as a HOST: `role=host` in the query beside the token. The
/// core gives the menu's actions to a host alone, and only a native client
/// can be one — a `URLSession` websocket carries no Origin header, and the
/// core refuses the role to anything that does (every web page). While a
/// host is connected NEO.app keeps its menu-bar item away; NotchHub's
/// Settings carry that menu instead.
///
/// NEO may be off. The listener retries every `reconnectDelay` while the core
/// is not there, quietly: a missing token file or a refused connection is the
/// normal state of a Mac where NEO is not running, not an error worth a log
/// line. Only real transitions (came up, went away) are reported.
public final class NeoListener: NSObject, SystemListener {

    /// Where NEO's core listens.
    public static let defaultURL = URL(string: "ws://127.0.0.1:8765/")!
    /// The token NEO.app keeps for its websocket.
    public static let defaultTokenFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".neo/ws-token")
    /// How long after a failed or closed connection the next attempt is made.
    public static let defaultReconnectDelay: TimeInterval = 1.5
    /// No camera preview frames, please.
    public static let cameraOffCommand = #"{"cmd":"camera_view","visible":false}"#
    /// The camera panel is on screen: its preview frames, please.
    public static let cameraOnCommand = #"{"cmd":"camera_view","visible":true}"#
    /// Turn the camera off (whichever session is live; see `cameraStopCommand(sid:)`).
    public static let cameraStopCommand = #"{"cmd":"camera_stop"}"#
    /// The song card's state again, if one is open.
    public static let songHelloCommand = #"{"cmd":"song_hello"}"#
    /// NEO's UI lives in the notch: NEO.app keeps its window hidden.
    public static let hostNotchCommand = #"{"cmd":"ui_host","host":"notch"}"#
    /// …and it is NEO.app's again.
    public static let hostWindowCommand = #"{"cmd":"ui_host","host":"window"}"#

    private let url: URL
    private let tokenFile: URL
    private let reconnectDelay: TimeInterval
    /// Asked on every connection, not once: NEO's page may be installed
    /// after NotchHub started (NEO set up on a Mac where NotchHub already
    /// ran), and the next connection — NEO's install restarts its core —
    /// then takes NEO's UI into the notch without NotchHub restarting.
    private let hostsUI: () -> Bool
    /// Whether this connection took NEO's UI (`hostsUI` when it connected):
    /// only then is the UI handed back as the listener stops.
    private var hosting = false
    private let emit: (SystemEvent) -> Void

    /// Every piece of state below is touched only on this queue. The session
    /// delivers its callbacks here too, so there is no locking to get wrong.
    private let queue = DispatchQueue(label: "com.notchhub.neo")
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }()
    private var task: URLSessionWebSocketTask?
    private var isRunning = false
    private var isConnected = false
    private var reconnect: DispatchWorkItem?
    private var cameraSID: String?
    private var lastCameraFrameAt: TimeInterval = 0

    /// - Parameter hostsUI: whether NotchHub has NEO's UI to show in its
    ///   panel (`NeoUIBundle`), and so takes NEO's UI into the notch —
    ///   evaluated again on every connection.
    public init(
        url: URL = NeoListener.defaultURL,
        tokenFile: URL = NeoListener.defaultTokenFile,
        reconnectDelay: TimeInterval = NeoListener.defaultReconnectDelay,
        hostsUI: @autoclosure @escaping () -> Bool = false,
        emit: @escaping (SystemEvent) -> Void
    ) {
        self.url = url
        self.tokenFile = tokenFile
        self.reconnectDelay = reconnectDelay
        self.hostsUI = hostsUI
        self.emit = emit
    }

    public var name: String { "NEO" }

    public func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            connect()
        }
    }

    public func stop() {
        // Hands NEO its UI back before letting go, and waits (briefly) for
        // that to leave: the app is usually quitting, and a command still in
        // the socket's buffer when the process ends never arrives. Best
        // effort — a core that is not there to take it is not waited for.
        let handedBack = DispatchSemaphore(value: 0)
        queue.async { [self] in
            guard isRunning else { handedBack.signal(); return }
            isRunning = false
            reconnect?.cancel()
            reconnect = nil
            let socket = task
            task = nil
            if let socket, isConnected, hosting {
                socket.send(.string(Self.hostWindowCommand)) { _ in
                    socket.cancel(with: .goingAway, reason: nil)
                    handedBack.signal()
                }
            } else {
                socket?.cancel(with: .goingAway, reason: nil)
                handedBack.signal()
            }
            if isConnected {
                isConnected = false
                emit(SystemEvent(source: .neo, payload: .neo(.connected(false))))
            }
        }
        _ = handedBack.wait(timeout: .now() + Self.handBackTimeout)
    }

    /// How long `stop` waits for `ui_host window` to leave.
    static let handBackTimeout: TimeInterval = 0.4

    // MARK: - Connecting

    /// The token, read fresh for every attempt (NEO.app may rewrite it), or
    /// `nil` when the file is not there or holds nothing usable.
    public static func readToken(at file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 64 hex characters from NEO.app; the core itself accepts anything of
        // 32+ URL-safe characters, so be exactly as strict as it is.
        guard token.count >= 32, token.unicodeScalars.allSatisfy({ CharacterSet.urlQueryAllowed.contains($0) && $0 != "&" && $0 != "=" }) else {
            return nil
        }
        return token
    }

    /// The socket URL carrying the token, and the listener's role: a host.
    static func socketURL(base: URL, token: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "token", value: token), URLQueryItem(name: "role", value: "host")]
        return components.url
    }

    // MARK: - NEO.app's menu

    /// Asks NEO.app (through its core) for one of its menu's actions. Dropped
    /// when the core is not connected: there is nobody to ask, and a command
    /// kept for later would run at a moment the user did not choose.
    public func send(_ action: NeoShellAction) {
        queue.async { [self] in
            guard isRunning, isConnected, let task else {
                NotchLog.debug("neo: \(action.name) not sent — no core")
                return
            }
            task.send(.string(action.command)) { _ in }
        }
    }

    // MARK: - The core's settings

    /// Switches one of the core's settings ("Listen for 'Neo'"). Dropped when
    /// the core is not connected: a switch flipped later, by itself, would
    /// turn the microphone on or off at a moment the user did not choose.
    public func send(_ setting: NeoSetting) {
        queue.async { [self] in
            guard isRunning, isConnected, let task else {
                NotchLog.debug("neo: set \(setting.name) not sent — no core")
                return
            }
            task.send(.string(setting.command)) { _ in }
        }
    }

    // MARK: - NEO's Allow / Cancel

    /// Answers a pending confirmation: the user pressed Allow or Cancel under
    /// the notch. Dropped when the core is not connected — an answer kept for
    /// later would approve something at a moment the user did not choose.
    public func send(_ answer: NeoConfirmAnswer) {
        queue.async { [self] in
            guard isRunning, isConnected, let task else {
                NotchLog.debug("neo: confirm answer not sent — no core")
                return
            }
            task.send(.string(answer.command)) { _ in }
        }
    }

    /// Lets NEO stream preview frames only while its native notch surface is
    /// visible. A hidden client receives no camera pixels.
    public func setCameraVisible(_ visible: Bool) {
        queue.async { [self] in
            guard isRunning, isConnected, let task else { return }
            task.send(.string(visible ? Self.cameraOnCommand : Self.cameraOffCommand)) { _ in }
        }
    }

    /// Stops NEO's camera session when the user closes its native notch card
    /// (or another panel covers it). Naming the session means a stop that
    /// arrives late never stops a newer one: the core ignores a stop for a
    /// session that is not its current one.
    public func stopCamera(sid: String? = nil) {
        queue.async { [self] in
            guard isRunning, isConnected, let task else { return }
            task.send(.string(Self.cameraStopCommand(sid: sid))) { _ in }
        }
    }

    /// `camera_stop`, naming the session when it is known.
    static func cameraStopCommand(sid: String?) -> String {
        guard let sid, !sid.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: ["cmd": "camera_stop", "sid": sid], options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return cameraStopCommand }
        return text
    }

    private func connect() {
        guard isRunning, task == nil else { return }
        guard let token = Self.readToken(at: tokenFile), let socketURL = Self.socketURL(base: url, token: token) else {
            // No NEO.app on this Mac (yet): look again later, touching nothing
            // but that one file.
            scheduleReconnect()
            return
        }
        var request = URLRequest(url: socketURL)
        request.timeoutInterval = 10
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        // Queued behind the handshake: no camera frames until NotchHub's
        // camera panel is actually on screen (`setCameraVisible(true)`).
        task.send(.string(Self.cameraOffCommand)) { _ in }
        hosting = hostsUI()
        if hosting {
            // NEO's UI is in the notch from here on: NEO.app hides its window.
            task.send(.string(Self.hostNotchCommand)) { _ in }
        }
        // Recover an in-flight song card if NotchHub connects after it opened.
        task.send(.string(Self.songHelloCommand)) { _ in }
        receive(on: task)
    }

    private func scheduleReconnect() {
        guard isRunning, reconnect == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnect = nil
            self.connect()
        }
        reconnect = item
        queue.asyncAfter(deadline: .now() + reconnectDelay, execute: item)
    }

    /// The socket is gone (closed, refused, or failed): note it and try again.
    private func dropped(_ task: URLSessionWebSocketTask) {
        guard self.task === task else { return }
        self.task = nil
        if isConnected {
            isConnected = false
            NotchLog.debug("neo: core went away")
            emit(SystemEvent(source: .neo, payload: .neo(.connected(false))))
        }
        scheduleReconnect()
    }

    // MARK: - Receiving

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            // The delegate queue is ours, but `receive` may answer elsewhere.
            self.queue.async {
                guard self.task === task else { return }
                switch result {
                case let .success(message):
                    if case let .string(text) = message {
                        self.updateCameraSession(from: text)
                        if let status = Self.shellStatus(in: text) {
                            self.emit(SystemEvent(source: .neo, payload: .neoShell(status)))
                        }
                        if let settings = Self.coreSettings(in: text) {
                            self.emit(SystemEvent(source: .neo, payload: .neoSettings(settings)))
                        }
                        if let brains = Self.brainStatus(in: text) {
                            self.emit(SystemEvent(source: .neo, payload: .neoBrains(brains)))
                        }
                        for fact in Self.facts(in: text) {
                            self.emit(SystemEvent(source: .neo, payload: .neo(fact)))
                        }
                    } else if case let .data(frame) = message,
                              let (sid, image) = Self.cameraImage(in: frame),
                              sid == self.cameraSID {
                        let now = Date.timeIntervalSinceReferenceDate
                        if Self.cameraFrameDue(at: now, after: self.lastCameraFrameAt) {
                            self.lastCameraFrameAt = now
                            self.emit(SystemEvent(source: .neo, payload: .neo(.cameraFrame(image))))
                        }
                    }
                    // Every other binary frame (a browser card's page, another
                    // session's camera, a malformed packet) is not for us.
                    self.receive(on: task)
                case .failure:
                    self.dropped(task)
                }
            }
        }
    }

    // MARK: - Parsing

    /// What NEO.app's shell reported, when a message carries it: the `shell`
    /// object of the core's `hello`, or a `shell_status` event. `nil` for
    /// every other message, and for a hello from a core too old to send one.
    public static func shellStatus(in text: String) -> NeoShellStatus? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        let payload = object["data"] as? [String: Any] ?? [:]
        switch type {
        case "hello": return (payload["shell"] as? [String: Any]).flatMap(NeoShellStatus.init(payload:))
        case "shell_status": return NeoShellStatus(payload: payload)
        default: return nil
        }
    }

    /// What the core said about its own settings, when a message carries it:
    /// every `hello` (one from a core too old to have the setting says
    /// "unknown", so nothing from an earlier connection lingers), and a
    /// `settings` event that names a setting this host knows. `nil` for
    /// every other message — a host's own `set_result` among them: the
    /// switch follows what the core announces, not what it was asked.
    public static func coreSettings(in text: String) -> NeoCoreSettings? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        let payload = object["data"] as? [String: Any] ?? [:]
        switch type {
        case "hello": return NeoCoreSettings(payload: payload)
        case "settings":
            let settings = NeoCoreSettings(payload: payload)
            return settings.wakeWord == nil && settings.wellbeingCheckins == nil ? nil : settings
        default: return nil
        }
    }

    /// What the core said about its brains, when a message carries it: every
    /// `hello` — `.some(nil)` from a core too old to have Brains & Keys (or
    /// one whose `brains` is not NEO's), so nothing from an earlier
    /// connection lingers — and a `brains` event that is NEO's. `nil` (the
    /// outer one) for every other message, a `brains` event that is not
    /// NEO's among them: it says nothing, so what was known stays.
    public static func brainStatus(in text: String) -> NeoBrainStatus?? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        let payload = object["data"] as? [String: Any] ?? [:]
        switch type {
        case "hello":
            return .some((payload["brains"] as? [String: Any]).flatMap(NeoBrainStatus.init(payload:)))
        case "brains":
            return NeoBrainStatus(payload: payload).map { .some($0) }
        default:
            return nil
        }
    }

    /// The facts in one message from the core. A card's opening and closing
    /// (`browser_open` / `browser_close`, camera, song) are facts for the
    /// panel; a confirmation staged or over is one for the island's Allow /
    /// Cancel; NEO's timers (the hello's, and `activity` events of kind
    /// `timer`) are for its countdown; everything else — the cards' own
    /// state, tool calls, turn metadata — is not the island's business and
    /// yields nothing.
    public static func facts(in text: String) -> [NeoFact] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        let payload = object["data"] as? [String: Any] ?? [:]
        switch type {
        case "hello":
            // Only what NEO is doing NOW — its state, and a question still
            // waiting for an answer. The replayed `recent` events are the old
            // transcript, which must not pop up on the island.
            var facts: [NeoFact] = []
            if let state = (payload["state"] as? String).flatMap(NeoState.init(rawValue:)) {
                facts.append(.state(state))
            }
            if let pending = (payload["confirm"] as? [String: Any]).flatMap(NeoConfirmCard.init(payload:)) {
                facts.append(.confirm(pending))
            }
            // A camera NEO already has on (NotchHub connected after it
            // opened): its state, then its opening — the session first, so
            // the island knows which one it is before it shows it.
            if let camera = payload["camera"] as? [String: Any],
               let live = camera["live"] as? [String: Any],
               let card = cameraCard(live) {
                facts.append(.cameraCard(card))
                facts.append(.card(.camera, open: true))
            }
            // NEO's timers counting down now: all of them, replacing whatever
            // the island knew (an empty list says there are none). A core too
            // old to have timers says nothing, and nothing new comes of it.
            if let timers = payload["timers"] as? [Any] {
                let entries = timers.prefix(NeoTimers.maxTimers).compactMap { ($0 as? [String: Any]).flatMap(NeoTimerInfo.init(payload:)) }
                facts.append(.neoTimers(entries))
            }
            return facts
        case "state":
            guard let state = (payload["state"] as? String).flatMap(NeoState.init(rawValue:)) else { return [] }
            return [.state(state)]
        case "transcript":
            guard let role = (payload["role"] as? String).flatMap(NeoRole.init(rawValue:)) else { return [] }
            let text = payload["text"] as? String ?? ""
            let final = payload["final"] as? Bool ?? false
            return [.transcript(role: role, text: text, final: final)]
        case "note":
            return [.note(payload["text"] as? String ?? "")]
        case "error":
            return [.error(payload["message"] as? String ?? "")]
        case "browser_open": return [.card(.browser, open: true)]
        case "browser_close": return [.card(.browser, open: false)]
        case "camera_open":
            // The new session's first state ("starting", which NEO says next
            // anyway), then the opening: the island learns which session
            // opens before it opens it.
            var facts: [NeoFact] = []
            if let card = cameraCard(payload, status: "starting") { facts.append(.cameraCard(card)) }
            facts.append(.card(.camera, open: true))
            return facts
        case "camera_state": return cameraCard(payload).map { [.cameraCard($0)] } ?? []
        case "camera_close": return [.card(.camera, open: false)]
        case "song_open":
            var facts: [NeoFact] = []
            if let sid = payload["sid"] as? String, !sid.isEmpty {
                facts.append(.songCard(NeoSongCardState(sid: sid, status: "listening")))
            }
            facts.append(.card(.song, open: true))
            return facts
        case "song_state": return songCard(payload).map { [.songCard($0)] } ?? []
        case "song_close": return [.card(.song, open: false)]
        case "woke": return [.woke] // summoned by hand (the hotkey, the tray)
        case "confirm":
            // NEO waits for an OK. Without an action id there is nothing an
            // answer could name: no buttons.
            return NeoConfirmCard(payload: payload).map { [.confirm($0)] } ?? []
        case "confirm_done":
            guard let id = payload["action_id"] as? String, !id.isEmpty else { return [] }
            return [.confirmDone(id)]
        case "activity":
            return timerActivity(payload).map { [$0] } ?? []
        default:
            return []
        }
    }

    /// One of NEO's timers starting (`op: present`) or over (`op: end`,
    /// `done` when it went off rather than being cancelled). `nil` for any
    /// other kind of activity — later kinds may share the event — and for
    /// anything without an id, or a start without its end time.
    private static func timerActivity(_ payload: [String: Any]) -> NeoFact? {
        guard payload["kind"] as? String == "timer" else { return nil }
        switch payload["op"] as? String {
        case "present":
            return NeoTimerInfo(payload: payload).map(NeoFact.neoTimer)
        case "end":
            guard let id = NeoTimerInfo.id(payload["id"]) else { return nil }
            // Only a real boolean says it went off: anything else is a cancel.
            let done = (payload["done"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
            return .neoTimerEnd(id: id, title: NeoTimerInfo.title(payload["title"]), done: done)
        default:
            return nil
        }
    }

    /// A camera card's state; `status` stands in when the payload has none
    /// (`camera_open` carries only the session and its reason).
    private static func cameraCard(_ payload: [String: Any], status fallback: String? = nil) -> NeoCameraCardState? {
        guard let sid = payload["sid"] as? String, !sid.isEmpty,
              let status = payload["status"] as? String ?? fallback else { return nil }
        let labels = (payload["labels"] as? [String] ?? []).prefix(8).map { String($0.prefix(40)) }
        let boxes = ((payload["boxes"] as? [[String: Any]]) ?? []).prefix(20).enumerated().compactMap { index, raw -> NeoCameraBox? in
            guard let x = (raw["x"] as? NSNumber)?.doubleValue,
                  let y = (raw["y"] as? NSNumber)?.doubleValue,
                  let w = (raw["w"] as? NSNumber)?.doubleValue,
                  let h = (raw["h"] as? NSNumber)?.doubleValue,
                  w > 0, h > 0 else { return nil }
            let id = (raw["id"] as? NSNumber)?.intValue ?? index
            let label = String((raw["label"] as? String ?? "").prefix(40))
            let score = min(1, max(0, (raw["score"] as? NSNumber)?.doubleValue ?? 0))
            let normalizedX = min(1, max(0, x))
            let normalizedY = min(1, max(0, y))
            return NeoCameraBox(
                id: id,
                x: normalizedX,
                y: normalizedY,
                w: min(1 - normalizedX, max(0, w)),
                h: min(1 - normalizedY, max(0, h)),
                label: label,
                score: score
            )
        }
        return NeoCameraCardState(
            sid: sid,
            status: status,
            answer: (payload["answer"] as? String).map { String($0.prefix(500)) },
            labels: labels,
            boxes: boxes
        )
    }

    private static func songCard(_ payload: [String: Any]) -> NeoSongCardState? {
        guard let sid = payload["sid"] as? String, !sid.isEmpty,
              let status = payload["status"] as? String else { return nil }
        let result = payload["result"] as? [String: Any] ?? [:]
        return NeoSongCardState(
            sid: sid,
            status: status,
            level: min(1, max(0, (payload["level"] as? NSNumber)?.doubleValue ?? 0)),
            elapsed: max(0, (payload["elapsed_s"] as? NSNumber)?.doubleValue ?? 0),
            message: (payload["message"] as? String).map { String($0.prefix(300)) },
            title: (result["title"] as? String).map { String($0.prefix(120)) },
            artist: (result["artist"] as? String).map { String($0.prefix(120)) },
            album: (result["album"] as? String).map { String($0.prefix(120)) },
            // NEO sends the year as text, or null when it has none: only text
            // is a year (a null used to show as "<null>").
            year: (result["year"] as? String).map { String($0.prefix(12)) },
            cover: imageDataURI(result["cover"] as? String)
        )
    }

    private static func imageDataURI(_ value: String?) -> Data? {
        guard let value, value.hasPrefix("data:image/"), let comma = value.firstIndex(of: ",") else { return nil }
        let encoded = String(value[value.index(after: comma)...])
        guard encoded.utf8.count <= 1_500_000 else { return nil }
        return Data(base64Encoded: encoded)
    }

    private func updateCameraSession(from text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }
        let payload = object["data"] as? [String: Any] ?? [:]
        switch type {
        case "camera_open", "camera_state":
            cameraSID = payload["sid"] as? String
        case "camera_close":
            if cameraSID == (payload["sid"] as? String) { cameraSID = nil }
        case "hello":
            let live = (payload["camera"] as? [String: Any])?["live"] as? [String: Any]
            cameraSID = live?["sid"] as? String
        default:
            break
        }
    }

    /// The preview's pace: at most 24 camera frames a second reach the island,
    /// however fast NEO sends them.
    static let cameraFrameInterval: TimeInterval = 1.0 / 24.0

    /// Whether a camera frame arriving at `now` goes on to the island, the
    /// last one having gone at `last` (both reference-date seconds).
    static func cameraFrameDue(at now: TimeInterval, after last: TimeInterval) -> Bool {
        now - last >= cameraFrameInterval
    }

    /// NBF1 v1 camera packet: the first 64 bytes are metadata, the rest JPEG.
    /// Reject other frame kinds, oversized payloads and stale/malformed headers.
    /// Returns the session id (as NEO writes it in JSON) and the image bytes.
    static func cameraImage(in packet: Data) -> (String, Data)? {
        guard packet.count >= 64, packet.count <= 2_000_000,
              packet.prefix(4) == Data("NBF1".utf8), packet[4] == 1, packet[5] == 3 else { return nil }
        let header = Int(packet[6]) | Int(packet[7]) << 8
        guard header >= 64, header <= packet.count else { return nil }
        let sidBytes = packet.subdata(in: 8..<24)
        let sid = sidBytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let mime = packet[56]
        guard mime == 1 else { return nil } // NEO currently streams JPEG camera frames.
        let image = packet.subdata(in: header..<packet.count)
        return image.isEmpty ? nil : (sid, image)
    }
}

extension NeoListener: URLSessionWebSocketDelegate {

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard task === webSocketTask, !isConnected else { return }
        isConnected = true
        NotchLog.debug("neo: connected to the core")
        emit(SystemEvent(source: .neo, payload: .neo(.connected(true))))
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        dropped(webSocketTask)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let socket = task as? URLSessionWebSocketTask else { return }
        dropped(socket)
    }
}
