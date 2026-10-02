import Foundation
import NotchHubCore

/// Listens to NEO's core over its local websocket and relays what it says.
///
/// NEO (the voice assistant) runs its own core at `ws://127.0.0.1:8765`, which
/// only admits clients that know the token NEO.app keeps in `~/.neo/ws-token`.
/// This listener is a second client beside NEO's own overlay: it reads that
/// one file (nothing else under `~/.neo`), connects with the token, and turns
/// the core's `hello` / `state` / `transcript` / `note` / `error` messages and
/// its card openings (`browser_open` …) and its `woke` (NEO summoned by hand)
/// into `NeoFact`s — and what NEO.app's shell reported (the hello's `shell`,
/// and `shell_status`) into a `NeoShellStatus`. A confirmation NEO stages
/// (`confirm`, or the one pending in the `hello`) and its end
/// (`confirm_done`) are facts too: the island's Allow / Cancel. What the core
/// says about its own settings (the hello's `wake_word`, and `settings`) is a
/// `NeoCoreSettings`. It sends five
/// kinds of command and nothing else, ever: `camera_view visible:false`, so
/// the core never streams camera frames to a client that cannot show them;
/// when NotchHub hosts NEO's UI (`hostsUI`), `ui_host notch` on every
/// connection and `ui_host window` as it stops, so NEO.app keeps its own
/// window hidden while the notch shows NEO and brings it back afterwards;
/// `shell` (`send(_:)`), one of NEO.app's menu actions, when the user
/// asks for it in Settings; `set` (`send(_:)` with a setting), when the user
/// flips "Listen for 'Neo'" there — the core takes it from a host; and
/// `confirm` (`send(_:)` with an answer), when
/// the user presses Allow or Cancel under the notch — the very command NEO's
/// own page sends from its card, naming the card's action id.
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
    /// NEO's UI lives in the notch: NEO.app keeps its window hidden.
    public static let hostNotchCommand = #"{"cmd":"ui_host","host":"notch"}"#
    /// …and it is NEO.app's again.
    public static let hostWindowCommand = #"{"cmd":"ui_host","host":"window"}"#

    private let url: URL
    private let tokenFile: URL
    private let reconnectDelay: TimeInterval
    private let hostsUI: Bool
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

    /// - Parameter hostsUI: whether NotchHub has NEO's UI to show in its
    ///   panel (`NeoUIBundle`), and so takes NEO's UI into the notch.
    public init(
        url: URL = NeoListener.defaultURL,
        tokenFile: URL = NeoListener.defaultTokenFile,
        reconnectDelay: TimeInterval = NeoListener.defaultReconnectDelay,
        hostsUI: Bool = false,
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
            if let socket, isConnected, hostsUI {
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
        // Queued behind the handshake; the core ignores a client's camera
        // messages until it shows the card, and this one never will.
        task.send(.string(Self.cameraOffCommand)) { _ in }
        if hostsUI {
            // NEO's UI is in the notch from here on: NEO.app hides its window.
            task.send(.string(Self.hostNotchCommand)) { _ in }
        }
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
                        if let status = Self.shellStatus(in: text) {
                            self.emit(SystemEvent(source: .neo, payload: .neoShell(status)))
                        }
                        if let settings = Self.coreSettings(in: text) {
                            self.emit(SystemEvent(source: .neo, payload: .neoSettings(settings)))
                        }
                        for fact in Self.facts(in: text) {
                            self.emit(SystemEvent(source: .neo, payload: .neo(fact)))
                        }
                    }
                    // Binary frames (page and camera pictures) are not for us.
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
            return settings.wakeWord == nil ? nil : settings
        default: return nil
        }
    }

    /// The facts in one message from the core. A card's opening and closing
    /// (`browser_open` / `browser_close`, camera, song) are facts for the
    /// panel; a confirmation staged or over is one for the island's Allow /
    /// Cancel; everything else — the cards' own state, tool calls, turn
    /// metadata — is not the island's business and yields nothing.
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
            let pending = (payload["confirm"] as? [String: Any]).flatMap(NeoConfirmCard.init(payload:)).map { [NeoFact.confirm($0)] } ?? []
            guard let state = (payload["state"] as? String).flatMap(NeoState.init(rawValue:)) else { return pending }
            return [.state(state)] + pending
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
        case "camera_open": return [.card(.camera, open: true)]
        case "camera_close": return [.card(.camera, open: false)]
        case "song_open": return [.card(.song, open: true)]
        case "song_close": return [.card(.song, open: false)]
        case "woke": return [.woke] // summoned by hand (the hotkey, the tray)
        case "confirm":
            // NEO waits for an OK. Without an action id there is nothing an
            // answer could name: no buttons.
            return NeoConfirmCard(payload: payload).map { [.confirm($0)] } ?? []
        case "confirm_done":
            guard let id = payload["action_id"] as? String, !id.isEmpty else { return [] }
            return [.confirmDone(id)]
        default:
            return []
        }
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
