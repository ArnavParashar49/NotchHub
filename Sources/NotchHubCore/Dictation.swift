import Foundation

/// Where a dictation run has got to.
public enum DictationPhase: Equatable {
    case idle
    /// Capturing speech.
    case listening
    /// Committing the final transcript.
    case finishing
    /// Stopped on an error the user should see.
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .listening, .finishing: return true
        case .idle, .failed: return false
        }
    }
}

/// A dictation run: on-device speech turned into text at the caret.
///
/// The island shows this while `⌥⌘M` is held down, so the user can see that
/// the Mac is listening and what it has heard so far.
public struct DictationSession: Equatable {
    public var phase: DictationPhase
    /// What has been recognised so far, updated as phrases finalise.
    public var transcript: String
    public let startedAt: Date?
    /// Input level, 0…1, for the waveform. Purely presentational.
    public var level: Double

    public init(
        phase: DictationPhase = .idle,
        transcript: String = "",
        startedAt: Date? = nil,
        level: Double = 0
    ) {
        self.phase = phase
        self.transcript = transcript
        self.startedAt = startedAt
        self.level = level
    }

    public var isActive: Bool { phase.isActive }

    /// `0:41` — how long the run has been going.
    public func elapsed(at now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    public func elapsedLabel(at now: Date = Date()) -> String {
        Activity.format(elapsed(at: now))
    }

    /// The line the island shows: what was heard, or a prompt to start.
    public var displayText: String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch phase {
        case .listening: return "Listening…"
        case .finishing: return "Finishing…"
        case .failed(let message): return message
        case .idle: return "Hold ⌥⌘M to dictate"
        }
    }
}

/// Where dictation's finished text should land.
public enum DictationDestination: Equatable {
    /// Type into whatever field currently has focus.
    case focusedField
    /// Hand the text back to the clipboard instead.
    case clipboard
}
