import Foundation
import NotchHubCore

/// Listens to NEO's core over its local websocket and relays what it says.
///
/// NEO (the voice assistant) runs its own core at `ws://127.0.0.1:8765`, which
/// only admits clients that know the token NEO.app keeps in `~/.neo/ws-token`.
/// This listener is a second client beside NEO's own overlay: it reads that
/// one file (nothing else under `~/.neo`), connects with the token, and turns
/// the core's `hello` / `state` / `transcript` / `note` / `error` messages into
/// `NeoFact`s. It sends exactly one command — `camera_view visible:false`, so
/// the core never streams camera frames to a client that cannot show them —
/// and nothing else, ever.
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
    /// The one command this client sends: no camera preview frames, please.
    public static let cameraOffCommand = #"{"cmd":"camera_view","visible":false}"#

    private let url: URL
    private let tokenFile: URL
    private let reconnectDelay: TimeInterval
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

    public init(
        url: URL = NeoListener.defaultURL,
        tokenFile: URL = NeoListener.defaultTokenFile,
        reconnectDelay: TimeInterval = NeoListener.defaultReconnectDelay,
        emit: @escaping (SystemEvent) -> Void
    ) {
        self.url = url
        self.tokenFile = tokenFile
        self.reconnectDelay = reconnectDelay
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
        queue.async { [self] in
            guard isRunning else { return }
            isRunning = false
            reconnect?.cancel()
            reconnect = nil
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            if isConnected {
                isConnected = false
                emit(SystemEvent(source: .neo, payload: .neo(.connected(false))))
            }
        }
    }

    // MARK: - Connecting

    /// The token, read fresh for every attempt (NEO.app may rewrite it), or
    /// `nil` when the file is not there or holds nothing usable.
    static func readToken(at file: URL) -> String? {
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

    /// The socket URL carrying the token.
    static func socketURL(base: URL, token: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
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

    /// The facts in one message from the core. Everything else — browser,
    /// camera and song cards, tool calls, turn metadata, confirmations — is
    /// not the lane's business and yields nothing.
    public static func facts(in text: String) -> [NeoFact] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        let payload = object["data"] as? [String: Any] ?? [:]
        switch type {
        case "hello":
            // Only what NEO is doing NOW. The replayed `recent` events are the
            // old transcript, which must not pop up on the island.
            guard let state = (payload["state"] as? String).flatMap(NeoState.init(rawValue:)) else { return [] }
            return [.state(state)]
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
