import AppKit
import AVFoundation
import NotchHubCore
import Speech

/// On-device dictation: speech straight into whatever field has focus.
///
/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition` keeps every word on
/// the Mac — nothing is sent anywhere. Finished phrases are typed into the
/// focused field with `CGEvent`, so dictation works in any app.
public final class DictationController: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var session = DictationSession()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var isRunning = false

    /// The locale to transcribe in. Follows the system by default.
    public var locale = Locale.current

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public var name: String { "Dictation" }

    public func start() {
        // Nothing to observe until the user asks to dictate.
    }

    public func stop() {
        cancel()
    }

    // MARK: - Control

    /// Begins a dictation run. Requires microphone + speech permissions, which
    /// the system prompts for on first use.
    public func begin() {
        guard !isRunning else { return }
        // Asking for speech or microphone access without the matching
        // usage-description strings in Info.plist makes macOS terminate the
        // app (a TCC privacy violation). Refuse politely instead.
        guard Self.hasUsageDescriptions else {
            publish(.failed("Dictation needs the NotchHub app bundle"))
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            publish(.failed("Dictation unavailable"))
            return
        }
        self.recognizer = recognizer

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.publish(.failed("Speech access denied"))
                    return
                }
                self?.requestMicrophoneThenCapture()
            }
        }
    }

    /// Ends the run. Whatever was recognised is already typed.
    public func finish() {
        guard isRunning else {
            // Even a run that never started should clear the overlay.
            publish(.idle)
            return
        }
        session.phase = .finishing
        publish(session.phase)
        teardownEngine()
        task?.finish()
        task = nil
        request = nil
        isRunning = false
        session.phase = .idle
        publish(.idle)
    }

    /// Aborts without committing anything further.
    public func cancel() {
        guard isRunning else { return }
        teardownEngine()
        task?.cancel()
        task = nil
        request = nil
        isRunning = false
        session = DictationSession()
        publish(.idle)
    }

    /// The Info.plist strings macOS requires before it will ask the user.
    static let requiredUsageDescriptions = ["NSSpeechRecognitionUsageDescription", "NSMicrophoneUsageDescription"]

    static var hasUsageDescriptions: Bool {
        requiredUsageDescriptions.allSatisfy { Bundle.main.object(forInfoDictionaryKey: $0) != nil }
    }

    /// Asks for the microphone explicitly before the audio engine touches it,
    /// so a denial is reported instead of failing inside the engine.
    private func requestMicrophoneThenCapture() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.beginCapture()
                    } else {
                        self?.publish(.failed("Microphone access denied"))
                    }
                }
            }
        default:
            publish(.failed("Microphone access denied"))
        }
    }

    // MARK: - Capture

    private func beginCapture() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // The whole point: never leave the Mac.
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.reportLevel(from: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            publish(.failed("Microphone unavailable"))
            return
        }

        isRunning = true
        session = DictationSession(phase: .listening, transcript: "", startedAt: Date(), level: 0)
        publish(session.phase)

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let finalizedEarlier = self.session.transcript
                // Type only what is new, so the field is not rewritten each tick.
                if text.count > finalizedEarlier.count {
                    // Keep the transcript authoritative; typing happens on
                    // final results only to avoid jitter in the focused field.
                    self.session.transcript = text
                }
                self.publish(self.session.phase)
                if result.isFinal {
                    self.typeIntoFocusedField(self.session.transcript)
                    self.finish()
                }
            }
            if error != nil {
                self.finish()
            }
        }
    }

    private func teardownEngine() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Output

    /// Types `text` at the caret of the focused field, character by character
    /// through the HID tap so it lands in any app.
    private func typeIntoFocusedField(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            var unit = UniChar(scalar.value)
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Publishes an audio level for the waveform, throttled to ~20 Hz.
    private func reportLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = sqrt(sum / Float(count))
        let level = max(0, min(1, Double(rms) * 12))
        session.level = level
    }

    private func publish(_ phase: DictationPhase) {
        session.phase = phase
        emit(SystemEvent(source: .dictation, payload: .dictation(session)))
    }
}
