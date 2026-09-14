import Foundation

/// A named pet animation. Frame names refer to `art/pet/*.pet` (see
/// `art/pet/SPEC.md`); a trailing `~` draws the frame mirrored.
/// `PetFrameTests` checks that every frame exists.
///
/// Mischief animations MOVE the sprite (`PetAnimation.offsets`). They are
/// authored for the pet's home on the RIGHT of the notch, where a negative `dx`
/// heads toward — and under — the notch. On the left of the notch the brain
/// mirrors the whole presentation: frames flip and `dx` negates.
public enum PetAnimationID: String, CaseIterable, Sendable {
    // Idle life
    case sit, blink, lookLeft, lookRight, breathe, tailWag, yawn, stretch, sleep, sleepZzz, wake
    // Noticing the user
    case alert, curious, wave, jump, happy, heart
    // Mischief at home
    case hop, blep, snicker, pounce, caught, pant
    // Mischief routines: hiding in the notch and crossing under it
    case sneakIn, dashIn, hidden, dashOut, tailPeek, peek, duck, duckTail, popOut
    // Music
    case music, musicExcited
    // Meetings
    case meetingTalk, meetingListen, meetingMuted, meetingCameraOff, meetingType
    // Coding agents
    case codeType, codeTypeBurst, codeThink, codeSearch, codeRun, codeAlert, codeDone
    // Timer, download, battery
    case timer, timerAlert, timerDone, download, downloadBurst, downloadDone, charging, lowBattery, fullCharge
    // Brief acknowledgements
    case notify, headphonesOn, headphonesOff, micOn, cameraOn, recordPoint, celebrate
    // Interaction
    case hiWave, pet, eat, play, stroke, leanLeft, leanRight

    public var animation: PetAnimation {
        typealias Cel = PetAnimation.Cel
        let hide = PetLayout.hiddenOffset
        let peekAt = PetLayout.peekOffset
        switch self {
        case .sit: return .still("sit")
        case .blink: return .once(["sit_blink"], 0.14)
        case .lookLeft: return .once(["sit_look_left", "sit_look_left", "sit_look_left", "sit"], 0.4)
        case .lookRight: return .once(["sit_look_right", "sit_look_right", "sit_look_right", "sit"], 0.4)
        case .breathe: return .once(["sit_breathe", "sit", "sit_breathe", "sit"], 0.6)
        case .tailWag: return .once(["sit_tail_1", "sit_tail_2", "sit_tail_1", "sit_tail_2", "sit"], 0.14)
        case .yawn: return .once(["yawn_1", "yawn_2", "yawn_2", "yawn_1", "sit"], 0.24)
        case .stretch: return .once(["stretch_1", "stretch_2", "stretch_2", "stretch_1", "sit"], 0.3)
        // Long-lived poses are STILL; their motion comes as bounded bursts the
        // brain schedules, so a resting pet never redraws continuously.
        case .sleep: return .still("sleep_1")
        case .sleepZzz: return .once(["sleep_2", "sleep_zzz", "sleep_zzz", "sleep_2", "sleep_1"], 0.8)
        case .wake: return .once(["wake", "sit_blink", "sit"], 0.3)

        case .alert: return .still("alert")
        case .curious: return .still("curious")
        case .wave: return .once(["wave_1", "wave_2", "wave_1", "wave_2", "alert"], 0.16)
        case .jump: return .once(["jump_crouch", "jump_air", "jump_crouch", "alert"], 0.11)
        case .happy: return .still("happy")
        case .heart: return .once(["heart", "heart", "happy"], 0.35)

        case .hop:
            // A springy little jump that really leaves the ground.
            // Peaks at 3 px: an 8-row hat still clears the top of a 32 pt notch.
            let heights = [0, -1, -2, -3, -2, -1, 0]
            let cels = heights.enumerated().map { Cel($0.offset == 0 || $0.offset == 6 ? "jump_crouch" : "jump_air", 0, $0.element) }
            return .path(cels + [Cel("sit")], 0.07)
        case .blep:
            return .once(Self.repeated("blep_1", 6) + Self.repeated("blep_2", 5) + Self.repeated("blep_1", 3) + ["sit"], 0.1)
        case .snicker:
            return .once(Self.alternating("snicker_1", "snicker_2", 8) + ["sit"], 0.14)
        case .pant:
            return .once(Self.alternating("pant_1", "pant_2", 10) + ["sit"], 0.22)
        case .caught:
            return .once(Self.repeated("caught", 9) + Self.repeated("blep_1", 5) + ["sit"], 0.1)
        case .pounce:
            // Wiggle, leap at the notch's edge, skid, trot back.
            let wiggle = Self.alternating("wiggle_1", "wiggle_2", 6).map { Cel($0) }
            let leap = [Cel("pounce", -2, -1), Cel("pounce", -4, -2), Cel("pounce", -6, -1), Cel("skid", -7), Cel("skid", -7)]
            let back = [Cel(Self.runFrame(0, mirrored: true), -5), Cel(Self.runFrame(2, mirrored: true), -3),
                        Cel(Self.runFrame(4, mirrored: true), -1), Cel("sit")]
            return .path(wiggle + leap + back, 0.1)

        case .sneakIn:
            // Creep toward the notch, then scurry under it.
            var cels = (0..<10).map { Cel($0 / 2 % 2 == 0 ? "sneak_1" : "sneak_2", -(($0 + 1) / 2)) }
            let scurry = [-9, -13, -17, -21, -25, hide]
            cels += scurry.enumerated().map { Cel(Self.runFrame($0.offset * 2), $0.element) }
            return .path(cels, 0.08)
        case .dashIn:
            let crouch = Array(repeating: Cel("wiggle_1"), count: 3)
            let dash = (1...(-hide / 2)).map { Cel(Self.runFrame($0 - 1), -2 * $0) }
            return .path(crouch + dash, 0.04)
        case .hidden:
            return .still("run_1", at: PetOffset(hide, 0))
        case .dashOut:
            // Out from under the notch, facing away from it, into a skid.
            let dash = (0..<(-hide / 2)).map { Cel(Self.runFrame($0, mirrored: true), hide + 2 + 2 * $0) }
            return .path(dash + Array(repeating: Cel("skid" + PetFrame.mirrorSuffix), count: 4), 0.04)
        case .tailPeek:
            let slide = [hide + 3, hide + 6, hide + 9].map { Cel("tail_peek_1", $0) }
            return .path(slide + Self.alternating("tail_peek_1", "tail_peek_2", 8).map { Cel($0, peekAt) }, 0.18)
        case .peek:
            let slide = [hide + 3, hide + 6, hide + 9].map { Cel("peek_1", $0) }
            let look = Self.repeated("peek_1", 5) + Self.repeated("peek_2", 4) + Self.repeated("peek_1", 3)
                + Self.repeated("peek_2", 3) + Self.repeated("peek_1", 2) + Self.repeated("peek_grin", 6)
            return .path(slide + look.map { Cel($0, peekAt) }, 0.1)
        case .duck:
            return .path([Cel("peek_1", peekAt - 3), Cel("peek_1", peekAt - 6), Cel("peek_1", peekAt - 9), Cel("run_1", hide)], 0.05)
        case .duckTail:
            return .path([Cel("tail_peek_1", peekAt - 3), Cel("tail_peek_1", peekAt - 6), Cel("tail_peek_1", peekAt - 9), Cel("run_1", hide)], 0.05)
        case .popOut:
            let arc: [(Int, Int)] = [(-14, -2), (-11, -3), (-8, -3), (-6, -3), (-4, -3), (-2, -2), (-1, -1), (0, 0)]
            return .path([Cel("peek_grin", peekAt), Cel("peek_grin", peekAt)]
                + arc.map { Cel("pop", $0.0, $0.1) }
                + [Cel("jump_crouch"), Cel("jump_crouch"), Cel("sit")], 0.05)

        case .music: return .loop(["music_1", "music_2", "music_3", "music_4"], 0.3)
        case .musicExcited: return .once(["music_excited", "music_2", "music_excited", "music_2"], 0.15)

        case .meetingTalk: return .loop(["meet_talk_1", "meet_talk_2"], 0.35)
        case .meetingListen: return .still("meet_listen")
        case .meetingMuted: return .still("meet_muted")
        case .meetingCameraOff: return .still("meet_camera_off")
        case .meetingType: return .loop(["meet_type_1", "meet_type_2"], 0.25)

        case .codeType: return .still("code_type_1")
        case .codeTypeBurst:
            return .once(["code_type_1", "code_type_2", "code_type_3", "code_type_2",
                          "code_type_1", "code_type_2", "code_type_3", "code_type_2", "code_type_1"], 0.18)
        case .codeThink: return .once(["code_think_1", "code_think_2", "code_think_1", "code_think_2", "code_type_1"], 0.6)
        case .codeSearch: return .once(["code_search_1", "code_search_2", "code_search_1", "code_search_2", "code_type_1"], 0.4)
        case .codeRun: return .still("code_run")
        case .codeAlert: return .still("code_alert")
        case .codeDone: return .once(["code_done", "celebrate_2", "code_done"], 0.35)

        case .timer: return .loop(["timer_1", "timer_2"], 0.8)
        case .timerAlert: return .loop(["timer_alert", "timer_1"], 0.25)
        case .timerDone: return .once(["timer_done", "celebrate_1", "celebrate_2", "celebrate_3"], 0.16)
        case .download: return .still("download_1")
        case .downloadBurst:
            return .once(["download_1", "download_2", "download_1", "download_2", "download_1", "download_2", "download_1"], 0.3)
        case .downloadDone: return .once(["download_done", "download_done", "celebrate_2"], 0.3)
        case .charging: return .loop(["charge_1", "charge_2"], 0.8)
        case .lowBattery: return .loop(["low_battery_1", "low_battery_2"], 0.7)
        case .fullCharge: return .once(["full_charge", "celebrate_2", "full_charge"], 0.3)

        case .notify: return .once(["notify", "notify", "alert"], 0.35)
        case .headphonesOn: return .once(["headphones_off", "headphones_on", "headphones_on"], 0.25)
        case .headphonesOff: return .once(["headphones_on", "headphones_off", "sit"], 0.25)
        case .micOn: return .once(["mic_on", "mic_on", "mic_on"], 0.4)
        case .cameraOn: return .once(["camera_on", "camera_on", "camera_on"], 0.4)
        case .recordPoint: return .once(["record_point", "record_point", "record_point"], 0.4)
        case .celebrate: return .once(["celebrate_1", "celebrate_2", "celebrate_3", "celebrate_2"], 0.14)

        case .hiWave: return .once(["hi_wave", "wave_2", "hi_wave"], 0.2)
        case .pet: return .once(["pet_1", "pet_2", "pet_1", "pet_2", "pet_1", "pet_2"], 0.3)
        case .eat: return .once(["eat_1", "eat_2", "eat_1", "eat_2"], 0.3)
        case .play: return .once(["play_1", "play_2", "play_1", "play_2"], 0.25)
        case .stroke: return .loop(["pet_1", "pet_2"], 0.3)
        case .leanLeft: return .still("lean_left")
        case .leanRight: return .still("lean_right")
        }
    }

    /// Where this animation leaves the pet during mischief: out on its dock,
    /// hidden inside the notch, or peeking out of it.
    public var mischiefPose: PetMischiefPose {
        switch self {
        case .sneakIn, .dashIn, .hidden, .duck, .duckTail: return .hidden
        case .tailPeek, .peek: return .peeking
        default: return .home
        }
    }

    /// The dash cycle: each of its four frames held for two ticks.
    private static func runFrame(_ tick: Int, mirrored: Bool = false) -> String {
        "run_\(tick / 2 % 4 + 1)" + (mirrored ? PetFrame.mirrorSuffix : "")
    }

    private static func repeated(_ frame: String, _ count: Int) -> [String] {
        Array(repeating: frame, count: count)
    }

    private static func alternating(_ first: String, _ second: String, _ count: Int) -> [String] {
        (0..<count).map { $0 % 2 == 0 ? first : second }
    }
}

/// Where the mischief leaves the pet.
public enum PetMischiefPose: Sendable {
    /// On its dock beside the notch.
    case home
    /// Wholly inside the notch, where the hardware hides it.
    case hidden
    /// Half out of the notch.
    case peeking
}

/// A sprite displacement in whole art pixels (points at 1×).
public struct PetOffset: Equatable, Sendable {
    public var dx: Int
    public var dy: Int

    public init(_ dx: Int, _ dy: Int) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = PetOffset(0, 0)
}

/// Frames and timing for one animation.
public struct PetAnimation: Equatable, Sendable {
    public let frames: [String]
    public let frameDuration: TimeInterval
    /// Loops forever; otherwise plays once and holds its last frame.
    public let loops: Bool
    /// Where the sprite is drawn on each frame, from its resting place. Empty:
    /// it stays put.
    public let offsets: [PetOffset]

    /// One drawn instant of a moving animation.
    public struct Cel {
        public let frame: String
        public let dx: Int
        public let dy: Int

        public init(_ frame: String, _ dx: Int = 0, _ dy: Int = 0) {
            self.frame = frame
            self.dx = dx
            self.dy = dy
        }
    }

    public static func still(_ frame: String, at offset: PetOffset = .zero) -> PetAnimation {
        PetAnimation(frames: [frame], frameDuration: 0, loops: false, offsets: offset == .zero ? [] : [offset])
    }

    public static func once(_ frames: [String], _ frameDuration: TimeInterval) -> PetAnimation {
        PetAnimation(frames: frames, frameDuration: frameDuration, loops: false, offsets: [])
    }

    public static func loop(_ frames: [String], _ frameDuration: TimeInterval) -> PetAnimation {
        PetAnimation(frames: frames, frameDuration: frameDuration, loops: true, offsets: [])
    }

    /// A one-shot that moves: every cel is a frame and where to draw it.
    public static func path(_ cels: [Cel], _ frameDuration: TimeInterval) -> PetAnimation {
        PetAnimation(
            frames: cels.map(\.frame),
            frameDuration: frameDuration,
            loops: false,
            offsets: cels.map { PetOffset($0.dx, $0.dy) }
        )
    }

    public var duration: TimeInterval {
        Double(frames.count) * frameDuration
    }

    public var isStatic: Bool {
        frames.count <= 1 || frameDuration <= 0
    }

    public func frameIndex(at elapsed: TimeInterval) -> Int {
        guard !isStatic else { return 0 }
        // A hair of slack: a TimelineView tick lands exactly on a frame boundary,
        // and floating-point division can put it a femtosecond short.
        let step = Int((max(0, elapsed) / frameDuration + 1e-6).rounded(.down))
        return loops ? step % frames.count : min(step, frames.count - 1)
    }

    public func frameName(at elapsed: TimeInterval) -> String {
        frames[frameIndex(at: elapsed)]
    }

    /// The sprite's offset on frame `index`.
    public func offset(forFrame index: Int) -> PetOffset {
        guard !offsets.isEmpty else { return .zero }
        return offsets[min(max(0, index), offsets.count - 1)]
    }

    public func offset(at elapsed: TimeInterval) -> PetOffset {
        offset(forFrame: frameIndex(at: elapsed))
    }

    /// Whether frames still change after `elapsed` — when false the renderer
    /// can stop redrawing entirely.
    public func isAnimating(at elapsed: TimeInterval) -> Bool {
        !isStatic && (loops || elapsed < duration)
    }
}
