import CoreGraphics
import Foundation

/// The pet's high-level state.
public enum PetMood: String, CaseIterable, Sendable {
    case idle, sleeping, curious, happy, music, timer, download, meeting, coding
    case charging, lowBattery, notification, celebrating, interaction, mischief, focus
    /// The pet is NEO, and NEO is doing something (`PetContext.neoState`).
    case neo
}

/// The small things the user can do with the pet.
public enum PetInteraction: String, CaseIterable, Sendable {
    /// In panel order.
    case pet, feed, play, trick, focus, sleep
}

/// Moments the pet reacts to. Sent by the coordinator; the brain decides
/// whether (and how) to react.
public enum PetEvent: Equatable, Sendable {
    case hoverEntered
    case petHovered
    case petClicked
    case interaction(PetInteraction)
    case songChanged
    case timerFinished
    case downloadFinished
    case agentFinished
    case agentNeedsApproval
    case chargingStarted
    case fullyCharged
    case lowBattery
    case headphonesConnected
    case headphonesDisconnected
    case notification(important: Bool)
    case microphoneOn
    case cameraOn
    case recordingStarted
    /// The cursor strokes the big pet in its panel.
    case bigPetStroked
    /// The big pet in its panel was clicked.
    case bigPetClicked
    /// A focus session ran its full length.
    case focusFinished
    /// Today is a holiday, greeted once.
    case holiday
}

/// The pet's games on its idle dock.
public enum PetMischief: String, CaseIterable, Sendable {
    /// Sneak into the notch and hide; maybe wag the tail out of it; peek out —
    /// sometimes from the other side — then pop out.
    case hideAndSeek
    /// Dash under the notch and out the other side.
    case crossOver
    /// There and back again, flat out, then pant.
    case zoomies
    /// Back to the right of the notch after a visit to the left.
    case returnHome
    /// Spotted mid-game: pops out, busted.
    case caught
}

/// One beat of mischief: what the pet does, and where its dock is meanwhile.
public struct PetMischiefStep: Equatable, Sendable {
    public let animation: PetAnimationID
    public let dock: PetDock
    public let duration: TimeInterval
}

/// What the island is doing, as far as the pet cares. Built by the coordinator
/// from state it already holds — the pet never looks at views.
public struct PetContext: Equatable, Sendable {
    public typealias Side = PetSide

    public var isHovering = false
    public var isPetHovered = false
    /// Which side of the pet the cursor is on while it is over the island.
    public var cursorSide: Side?
    public var interactionOpen = false
    public var isMusicPlaying = false
    public var inMeeting = false
    public var meetingMuted = false
    public var meetingCameraOn = true
    public var isAgentWorking = false
    public var isTimerRunning = false
    public var isDownloading = false
    public var isCharging = false
    public var batteryPercent: Int?
    /// Occasional flourishes in the calm moods (blink, look around, yawn, zzz…).
    /// Off leaves a resting pet perfectly still; activity animations and
    /// reactions are unaffected.
    public var idleFlourishes = true
    /// The island is resting with the pet's dock beside a real notch — the only
    /// place the pet may leave its spot.
    public var canRoam = false
    /// The Mischief setting: hiding in the notch, peeking, crossing under it,
    /// pouncing, sticking its tongue out.
    public var mischief = false
    /// A focus session is counting down.
    public var isFocusing = false
    /// The pet has its dock beside a real notch (whether or not the island
    /// rests right now) — where a requested trick can play.
    public var isDocked = false
    /// What NEO is doing, as its core reports it (after the dwell): the pet
    /// IS NEO, so this is its pose while NEO is busy. `nil` while NEO is
    /// off or away; `.idle` is NEO ready, which is the pet's own life.
    public var neoState: NeoState?

    public init() {}

    /// NEO is doing something: the pet shows it.
    public var isNeoBusy: Bool { (neoState ?? .idle) != .idle }

    public var isLowBattery: Bool {
        !isCharging && (batteryPercent ?? 100) <= 10
    }

    /// Everything that counts as the user or the Mac being busy — what keeps
    /// the pet awake while it lasts. (Charging and battery level do not.)
    var engagement: [Bool] {
        [isHovering, isPetHovered, interactionOpen, isMusicPlaying, inMeeting,
         isAgentWorking, isTimerRunning, isDownloading, isFocusing, isNeoBusy]
    }

    /// What wakes a pet the user put to sleep, when it STARTS: coming back to
    /// the notch, or the Mac starting something. Pointing at the pet or closing
    /// its panel does not.
    var wakeTriggers: [Bool] {
        [isHovering, isMusicPlaying, inMeeting, isAgentWorking, isTimerRunning, isDownloading, isFocusing, isNeoBusy]
    }
}

/// What the renderer should show.
public struct PetPresentation: Equatable, Sendable {
    public var mood: PetMood
    public var animation: PetAnimationID
    /// When `animation` started — frame 0 is shown at this instant.
    public var startedAt: Date
    /// Drawn flipped left-to-right with offsets negated: the pet is on the left
    /// of the notch.
    public var mirrored: Bool

    public init(mood: PetMood, animation: PetAnimationID, startedAt: Date, mirrored: Bool = false) {
        self.mood = mood
        self.animation = animation
        self.startedAt = startedAt
        self.mirrored = mirrored
    }
}

/// The Pet State Manager: turns island context and events into what the pet
/// is doing, and where on its dock it is doing it.
///
/// Pure and deterministic (time and randomness are injected), so every
/// behaviour is unit-tested. It never runs a timer itself: `nextWakeup` tells
/// the coordinator when something is next due (a reaction ending, a flourish,
/// a mischief beat, falling asleep), so an idle pet costs nothing in between.
///
/// Resolution, highest first:
/// 1. mischief in progress on the idle dock (it owns `dock`)
/// 2. a reaction to an event (celebrate, notice a notification, wake up…) —
///    which never cuts a pet mid-dash or mid-leap: it waits for the landing
/// 3. an occasional flourish within the current mood (blink, look around…)
/// 4. the mood's base pose: interaction › meeting › put to sleep › pet hovered
///    › island hovered › coding › timer › download › music › fell asleep ›
///    low battery › charging › idle
///
/// Mischief only plays while the island rests with the dock beside a real
/// notch (`PetContext.canRoam`), the pet is idle or charging, and Mischief and
/// Idle Animations are on. It never hides a moment: a reaction brings the pet
/// straight home, and anything else that needs it (sleep, an activity) lets
/// the current beat finish and sends the pet home the quick way. Leaving the
/// dock (hover, an activity, a panel) drops it at once — the island's own
/// spring carries the pet back to its place.
public struct PetBrain {

    public static let sleepAfter: TimeInterval = 180
    static let calmFlourishDelay: ClosedRange<Double> = 7...18
    static let hoverReactionCooldown: TimeInterval = 2.5
    /// Between two bits of mischief.
    public static let mischiefDelay: ClosedRange<Double> = 14...40
    /// From the island settling at rest to the first bit of mischief.
    public static let settleMischiefDelay: ClosedRange<Double> = 5...12
    /// How long the pet stays on the left of the notch before heading home.
    public static let awayStay: ClosedRange<Double> = 8...20
    /// A shrinking dock's critically damped spring is home by then.
    static let retractTime: TimeInterval = 0.5
    /// A growing dock is out far enough to dash into.
    static let growTime: TimeInterval = 0.35
    /// Swapping sides happens while the pet is hidden and the dock is closed.
    static let switchTime: TimeInterval = 0.05
    /// How long a game asked for from the panel waits for the island to rest.
    static let requestWindow: TimeInterval = 20
    /// How long the pet keeps purring after the last stroke.
    static let strokeHold: TimeInterval = 1.2

    public private(set) var presentation: PetPresentation
    /// Where the idle dock is and how far it reaches. The island follows it.
    public private(set) var dock = PetDock.home

    struct Timed: Equatable {
        let animation: PetAnimationID
        let mood: PetMood
        let until: Date
    }

    struct Base {
        let mood: PetMood
        let animation: PetAnimationID
        let flourishes: [PetAnimationID]
        let delay: ClosedRange<Double>
        /// A calm mood whose flourishes the Idle Animations setting controls.
        let calm: Bool
    }

    struct Routine {
        let kind: PetMischief
        var steps: [PetMischiefStep]
        var index = 0
        var stepStart: Date
        /// Already heading home; never re-planned.
        var windingUp = false
        /// Asked for from the panel's Tricks: plays whatever the Mischief
        /// setting says, as long as nothing needs the pet.
        var requested = false

        var step: PetMischiefStep { steps[index] }
        var stepEnd: Date { stepStart.addingTimeInterval(step.duration) }
    }

    /// A reaction that waits for the pet to land (see `canCut`).
    struct Pending: Equatable {
        let animation: PetAnimationID
        let mood: PetMood
        let hold: TimeInterval
    }

    /// A game asked for from the panel, waiting for the island to rest.
    struct Request: Equatable {
        let kind: PetMischief
        let until: Date
    }

    private var reaction: Timed?
    private var pendingReaction: Pending?
    private var requestedMischief: Request?
    /// The visit on the left came from a requested game.
    private var awayRequested = false
    private var lastRequested: PetMischief?
    private var lastTrick: PetAnimationID?
    private var flourish: Timed?
    private var routine: Routine?
    private var nextFlourishAt: Date
    private var nextMischiefAt: Date
    private var awayUntil: Date?
    private var mischiefWasAllowed = false
    private var lastEngagement: Date
    private var wasEngaged = false
    private var lastHoverReaction = Date.distantPast
    private var forcedSleep = false
    private var lastWakeTriggers: [Bool] = []
    private var rng: SplitMix64

    public init(now: Date = Date(), seed: UInt64 = 0x5EED_F0C5) {
        rng = SplitMix64(state: seed)
        presentation = PetPresentation(mood: .idle, animation: .sit, startedAt: now)
        lastEngagement = now
        nextFlourishAt = now
        nextMischiefAt = now
        nextFlourishAt = now.addingTimeInterval(randomDelay(Self.calmFlourishDelay))
    }

    /// The mischief being played, if any.
    public var mischief: PetMischief? { routine?.kind }

    /// The beats of the mischief being played (empty when none).
    public var mischiefSteps: [PetMischiefStep] { routine?.steps ?? [] }

    /// Which beat of `mischiefSteps` is playing.
    public var mischiefStepIndex: Int? { routine?.index }

    // MARK: - Inputs

    /// Re-evaluates the pet for the current context.
    @discardableResult
    public mutating func update(_ context: PetContext, now: Date) -> PetPresentation {
        let triggers = context.wakeTriggers
        let previous = lastWakeTriggers.count == triggers.count ? lastWakeTriggers : Array(repeating: false, count: triggers.count)
        if zip(triggers, previous).contains(where: { $0 && !$1 }) {
            forcedSleep = false
        }
        lastWakeTriggers = triggers
        // Sleep is counted from the END of the last engagement — including the
        // first update that finds it over, however long it lasted unobserved.
        let engaged = context.engagement.contains(true)
        if engaged || wasEngaged {
            lastEngagement = now
        }
        wasEngaged = engaged

        if let reaction, now >= reaction.until { self.reaction = nil }
        if let flourish, now >= flourish.until { self.flourish = nil }

        let base = baseState(context, now: now)
        let flourishes = activeFlourishes(base, context)
        // The dock as it is drawn right now, before this update moves it.
        let shownDock = dock

        // Waking up is a moment, not a cut.
        if presentation.mood == .sleeping, base.mood != .sleeping, reaction == nil {
            setReaction(.wake, mood: base.mood, until: now.addingTimeInterval(PetAnimationID.wake.animation.duration), now: now)
        }

        // A flourish the moment no longer offers ends once the pet has landed —
        // or at once when the island leaves the dock, whose spring carries it.
        if let current = flourish, current.mood != base.mood || !flourishes.contains(current.animation),
           !context.canRoam || drawnOffset(at: now) == .zero {
            flourish = nil
        }

        runMischief(context, base: base, now: now)

        // A moment that waited for the pet to land.
        if let pending = pendingReaction, reaction == nil, (routine == nil && flourish == nil) || canCut(at: now, shown: shownDock) {
            pendingReaction = nil
            if routine != nil {
                routine = nil
                awayUntil = nil
                awayRequested = false
                dock = .home
            }
            startReaction(pending.animation, pending.mood, hold: pending.hold, now: now)
        }

        if let routine {
            apply(.mischief, routine.step.animation, now: now)
            return presentation
        }

        if let reaction {
            apply(reaction.mood, reaction.animation, now: now)
            return presentation
        }

        if flourish == nil, now >= nextFlourishAt {
            if flourishes.isEmpty {
                nextFlourishAt = now.addingTimeInterval(randomDelay(base.delay))
            } else {
                let pick = flourishes[rng.index(flourishes.count)]
                flourish = Timed(animation: pick, mood: base.mood, until: now.addingTimeInterval(pick.animation.duration))
                nextFlourishAt = now.addingTimeInterval(pick.animation.duration + randomDelay(base.delay))
            }
        }

        // A flourish that outlived its mood keeps its own, so it is not restarted.
        apply(flourish?.mood ?? base.mood, flourish?.animation ?? base.animation, now: now)
        return presentation
    }

    /// Handles a moment the pet may react to, then re-evaluates.
    ///
    /// Only a moment the pet actually responds to counts as engagement or
    /// wakes a pet the user put to sleep — an ignored notification does not.
    @discardableResult
    public mutating func handle(_ event: PetEvent, context: PetContext, now: Date) -> PetPresentation {
        let asleep = presentation.mood == .sleeping
        var noticed = true

        switch event {
        case .hoverEntered:
            if context.mischief || routine?.requested == true || awayRequested, !asleep, routine != nil || dock != .home {
                // Caught in the act — but never over a celebration or an alert.
                if reactUnlessBusy(.caught, .curious, now: now) {
                    lastHoverReaction = now
                } else {
                    noticed = false
                }
            } else if !asleep, reaction == nil, now.timeIntervalSince(lastHoverReaction) >= Self.hoverReactionCooldown {
                lastHoverReaction = now
                let roll = rng.unit()
                if context.mischief {
                    let pick: PetAnimationID = roll < 0.3 ? .tailWag : roll < 0.55 ? .wave : roll < 0.7 ? .jump : roll < 0.85 ? .blep : .hop
                    react(pick, .curious, now: now)
                } else {
                    react(roll < 0.5 ? .tailWag : (roll < 0.85 ? .wave : .jump), .curious, now: now)
                }
            } else {
                noticed = false
            }
        case .petHovered:
            guard !asleep, !forcedSleep else {
                noticed = false
                break
            }
            if let current = routine, context.mischief || current.requested, current.kind != .caught {
                if beginCaught(from: current, now: now) {
                    lastHoverReaction = now
                } else {
                    noticed = false
                }
            } else if reaction == nil, pendingReaction == nil, now.timeIntervalSince(lastHoverReaction) >= Self.hoverReactionCooldown {
                lastHoverReaction = now
                if context.mischief {
                    let roll = rng.unit()
                    react(roll < 0.45 ? .wave : (roll < 0.8 ? .blep : .snicker), .curious, now: now)
                } else {
                    react(.wave, .curious, now: now)
                }
            } else {
                noticed = false
            }
        case .petClicked:
            react(.hiWave, .interaction, now: now)
        case let .interaction(action):
            switch action {
            case .pet: react(.pet, .happy, now: now)
            case .feed: react(.eat, .happy, now: now)
            case .play: react(.play, .happy, now: now)
            case .trick:
                if context.isDocked {
                    // A game on the dock, as soon as the island is at rest.
                    let kinds = [PetMischief.hideAndSeek, .crossOver, .zoomies].filter { Optional($0) != lastRequested }
                    let kind = kinds[rng.index(kinds.count)]
                    lastRequested = kind
                    requestedMischief = Request(kind: kind, until: now.addingTimeInterval(Self.requestWindow))
                } else {
                    playTrick(now: now)
                }
            case .focus:
                // The focus session itself is the context (`isFocusing`).
                break
            case .sleep:
                reaction = nil
                pendingReaction = nil
                requestedMischief = nil
                flourish = nil
                forcedSleep = true
            }
        case .songChanged:
            noticed = reactUnlessBusy(.musicExcited, .music, now: now)
        case .timerFinished:
            react(.timerDone, .celebrating, now: now)
        case .downloadFinished:
            react(.downloadDone, .celebrating, now: now)
        case .agentFinished:
            react(.codeDone, .celebrating, now: now)
        case .agentNeedsApproval:
            react(.codeAlert, .coding, now: now, hold: 4)
        case .chargingStarted:
            noticed = reactUnlessBusy(.charging, .charging, now: now, hold: 3.2)
        case .fullyCharged:
            react(.fullCharge, .celebrating, now: now)
        case .lowBattery:
            noticed = reactUnlessBusy(.lowBattery, .lowBattery, now: now, hold: 4.2)
        case .headphonesConnected:
            noticed = reactUnlessBusy(.headphonesOn, .happy, now: now)
        case .headphonesDisconnected:
            noticed = reactUnlessBusy(.headphonesOff, .idle, now: now)
        case let .notification(important):
            noticed = important && reactUnlessBusy(.notify, .notification, now: now)
        case .microphoneOn:
            noticed = reactUnlessBusy(.micOn, .notification, now: now)
        case .cameraOn:
            noticed = reactUnlessBusy(.cameraOn, .notification, now: now)
        case .recordingStarted:
            noticed = reactUnlessBusy(.recordPoint, .notification, now: now)
        case .bigPetStroked:
            guard !asleep else {
                noticed = false
                break
            }
            if let current = reaction, current.animation == .stroke, now < current.until {
                // Still being stroked: keep purring, never restart.
                setReaction(.stroke, mood: .happy, until: now.addingTimeInterval(Self.strokeHold), now: now)
            } else {
                react(.stroke, .happy, now: now, hold: Self.strokeHold)
            }
        case .bigPetClicked:
            guard !asleep else {
                noticed = false
                break
            }
            playTrick(now: now)
        case .focusFinished:
            react(.celebrate, .celebrating, now: now)
        case .holiday:
            noticed = reactUnlessBusy(.celebrate, .celebrating, now: now)
        }

        if noticed {
            lastEngagement = now
            if event != .interaction(.sleep), event != .petHovered {
                forcedSleep = false
            }
        }
        return update(context, now: now)
    }

    /// Starts a bit of mischief right now from wherever the pet is — for tests
    /// and the storyboard. The brain still stops it when the context says so.
    public mutating func startMischief(_ kind: PetMischief, now: Date) {
        guard kind != .caught else { return }
        begin(kind, plan(kind, from: dock.side), now: now)
    }

    /// When the brain next needs `update` — a reaction, flourish or mischief
    /// beat ending, a flourish or mischief due, or falling asleep. `nil` when
    /// nothing is scheduled.
    public func nextWakeup(context: PetContext, now: Date) -> Date? {
        var dates: [Date] = []
        if let routine { dates.append(routine.stepEnd) }
        if let reaction { dates.append(reaction.until) }
        if let flourish { dates.append(flourish.until) }
        let base = baseState(context, now: now)
        let busy = routine != nil || reaction != nil || flourish != nil
        if !busy, !activeFlourishes(base, context).isEmpty {
            dates.append(nextFlourishAt)
        }
        if !busy, context.canRoam {
            let allowed = awayRequested && dock.side == .left ? mayPlayOnRequest(context, base: base) : mayRoam(context, base: base)
            if dock.side == .left {
                if allowed {
                    dates.append(awayUntil ?? now)
                } else if !context.isPetHovered {
                    dates.append(now)
                }
            } else if allowed {
                dates.append(nextMischiefAt)
            }
        }
        if [.idle, .lowBattery, .charging].contains(base.mood) {
            dates.append(lastEngagement.addingTimeInterval(Self.sleepAfter))
        }
        guard let soonest = dates.min() else { return nil }
        return max(soonest, now.addingTimeInterval(0.05))
    }

    // MARK: - Resolution

    private func baseState(_ c: PetContext, now: Date) -> Base {
        func base(_ mood: PetMood, _ animation: PetAnimationID, _ flourishes: [PetAnimationID] = [],
                  delay: ClosedRange<Double> = Self.calmFlourishDelay, calm: Bool = false) -> Base {
            Base(mood: mood, animation: animation, flourishes: flourishes, delay: delay, calm: calm)
        }
        if c.interactionOpen {
            if c.isPetHovered, let side = c.cursorSide {
                // Leaning into the hand that points at it.
                return base(.interaction, side == .left ? .leanLeft : .leanRight, calm: true)
            }
            return base(.interaction, .happy, [.blink, .heart], calm: true)
        }
        if c.inMeeting {
            if c.meetingMuted { return base(.meeting, .meetingMuted) }
            if !c.meetingCameraOn { return base(.meeting, .meetingCameraOff) }
            return base(.meeting, .meetingListen, [.meetingType, .meetingTalk], delay: 4...10)
        }
        // The pet is NEO: while NEO is busy its pose is what NEO is doing,
        // over the cursor, sleep and every activity. Its poses animate on
        // their own, so they take no flourishes.
        if let neo = c.neoState, neo != .idle {
            return base(.neo, Self.neoAnimation(for: neo))
        }
        if forcedSleep {
            return base(.sleeping, .sleep, [.sleepZzz], delay: 14...28, calm: true)
        }
        if c.isPetHovered {
            return base(.curious, .happy, [.blink], calm: true)
        }
        if c.isHovering {
            let look: PetAnimationID
            switch c.cursorSide {
            case .left?: look = .lookLeft
            case .right?: look = .lookRight
            case nil: look = .tailWag
            }
            // Standing alert, glancing toward the cursor now and then.
            return base(.curious, .alert, [.blink, look], calm: true)
        }
        if c.isFocusing {
            // Working alongside you, quietly.
            return base(.focus, .codeType, [.codeTypeBurst, .codeTypeBurst, .codeThink], delay: 3...8)
        }
        if c.isAgentWorking {
            return base(.coding, .codeType, [.codeTypeBurst, .codeTypeBurst, .codeTypeBurst, .codeThink, .codeSearch], delay: 1.2...3.5)
        }
        if c.isTimerRunning {
            return base(.timer, .timer)
        }
        if c.isDownloading {
            return base(.download, .download, [.downloadBurst], delay: 0.8...2.5)
        }
        if c.isMusicPlaying {
            return base(.music, .music, [.musicExcited], delay: 12...30)
        }
        if now.timeIntervalSince(lastEngagement) >= Self.sleepAfter {
            return base(.sleeping, .sleep, [.sleepZzz], delay: 14...28, calm: true)
        }
        if c.isLowBattery {
            return base(.lowBattery, .sit, [.lowBattery, .blink], calm: true)
        }
        if c.isCharging {
            return base(.charging, .sit, [.charging, .blink, .tailWag], calm: true)
        }
        var idle: [PetAnimationID] = [.blink, .blink, .blink, .lookLeft, .lookRight, .tailWag, .breathe, .yawn, .stretch]
        if c.mischief {
            idle += [.blep, .hop, .snicker]
            if c.canRoam { idle += [.pounce, .pounce] }
        }
        return base(.idle, .sit, idle, calm: true)
    }

    /// The pose for what NEO is doing. Listening is attentive (ears up, a slow
    /// breath); thinking scratches its head; working paces; searching sniffs
    /// around with the magnifier; speaking talks to a cadence; needing an OK
    /// insists with its "!"; connecting wakes and stretches. Idle is the
    /// pet's own life.
    public static func neoAnimation(for state: NeoState) -> PetAnimationID {
        switch state {
        case .idle: return .sit
        case .connecting: return .neoWake
        case .listening: return .neoListen
        case .thinking: return .neoThink
        case .working: return .neoPace
        case .searching: return .neoSniff
        case .speaking: return .neoTalk
        case .confirming: return .neoAsk
        }
    }

    private func activeFlourishes(_ base: Base, _ context: PetContext) -> [PetAnimationID] {
        base.calm && !context.idleFlourishes ? [] : base.flourishes
    }

    private mutating func apply(_ mood: PetMood, _ animation: PetAnimationID, now: Date) {
        let mirrored = dock.side == .left
        guard mood != presentation.mood || animation != presentation.animation || mirrored != presentation.mirrored else { return }
        presentation = PetPresentation(mood: mood, animation: animation, startedAt: now, mirrored: mirrored)
    }

    private mutating func react(_ animation: PetAnimationID, _ mood: PetMood, now: Date, hold: TimeInterval? = nil) {
        let duration = hold ?? max(animation.animation.duration, 0.4)
        guard canCut(at: now, shown: dock) else {
            // Mid-dash or mid-leap: the moment waits for the pet to land.
            pendingReaction = Pending(animation: animation, mood: mood, hold: duration)
            return
        }
        pendingReaction = nil
        startReaction(animation, mood, hold: duration, now: now)
    }

    private mutating func startReaction(_ animation: PetAnimationID, _ mood: PetMood, hold: TimeInterval, now: Date) {
        setReaction(animation, mood: mood, until: now.addingTimeInterval(hold), now: now)
        // A repeated reaction restarts from its first frame.
        presentation = PetPresentation(mood: mood, animation: animation, startedAt: now, mirrored: dock.side == .left)
    }

    /// The sprite's offset as it is drawn right now.
    private func drawnOffset(at now: Date) -> PetOffset {
        presentation.animation.animation.offset(at: now.timeIntervalSince(presentation.startedAt))
    }

    /// Whether the pet can be cut to another pose without a visible jump, given
    /// the dock as it is drawn (`shown`). Without a game: when it stands still.
    /// During one: standing still on a full dock, or wholly hidden inside the
    /// notch where cutting home reveals it only as a CLOSED dock opens around it —
    /// the right dock closed, or the pet on the left (home is on the right, whose
    /// dock is closed while the pet is away).
    private func canCut(at now: Date, shown: PetDock? = nil) -> Bool {
        let offset = drawnOffset(at: now)
        guard routine != nil else { return offset == .zero }
        let shown = shown ?? dock
        // Standing still counts only on the right: cutting a standing pet on the
        // left home would swap the dock's side with the pet in view. There, a
        // moment waits for the quick way home.
        if offset == .zero { return shown.reach >= PetLayout.idleDock && shown.side == .right }
        return offset.dx <= PetLayout.hiddenOffset + 3 && (shown.reach == 0 || shown.side == .left)
    }

    private mutating func setReaction(_ animation: PetAnimationID, mood: PetMood, until: Date, now: Date) {
        reaction = Timed(animation: animation, mood: mood, until: until)
        flourish = nil
        // No flourish the instant a reaction ends.
        nextFlourishAt = max(nextFlourishAt, until.addingTimeInterval(randomDelay(Self.calmFlourishDelay)))
    }

    /// A minor reaction never cuts off a celebration or an alert in progress.
    /// Returns whether the pet reacted.
    private mutating func reactUnlessBusy(_ animation: PetAnimationID, _ mood: PetMood, now: Date, hold: TimeInterval? = nil) -> Bool {
        let important: [PetMood] = [.celebrating, .notification, .coding]
        if let reaction, now < reaction.until, important.contains(reaction.mood) {
            return false
        }
        if let pendingReaction, important.contains(pendingReaction.mood) {
            return false
        }
        react(animation, mood, now: now, hold: hold)
        return true
    }

    private mutating func randomDelay(_ range: ClosedRange<Double>) -> TimeInterval {
        range.lowerBound + rng.unit() * (range.upperBound - range.lowerBound)
    }

    // MARK: - Mischief

    /// Whether a game asked for from the panel may play: anything but a pet that
    /// is needed (a call, sleep, a reaction waiting) or being pointed at.
    private func mayPlayOnRequest(_ c: PetContext, base: Base) -> Bool {
        !c.isPetHovered && pendingReaction == nil && ![.meeting, .sleeping, .interaction, .curious].contains(base.mood)
    }

    /// A trick in place, never the same one twice in a row.
    private mutating func playTrick(now: Date) {
        let playing = reaction?.animation
        let tricks = [PetAnimationID.hop, .blep, .snicker, .wave, .jump, .heart]
            .filter { Optional($0) != lastTrick && Optional($0) != playing }
        let pick = tricks[rng.index(tricks.count)]
        lastTrick = pick
        react(pick, .happy, now: now)
    }

    /// Whether the pet may play on its dock right now (given the island rests).
    private func mayRoam(_ c: PetContext, base: Base) -> Bool {
        c.mischief && c.idleFlourishes && !c.isPetHovered && pendingReaction == nil && [.idle, .charging].contains(base.mood)
    }

    /// Starts, steps, winds up or drops mischief, and keeps `dock` in step.
    private mutating func runMischief(_ c: PetContext, base: Base, now: Date) {
        guard c.canRoam else {
            // Off the resting dock: the island is changing shape anyway, and its
            // spring carries the pet back to its place.
            routine = nil
            awayUntil = nil
            awayRequested = false
            dock = .home
            mischiefWasAllowed = false
            return
        }
        if let request = requestedMischief, now >= request.until {
            requestedMischief = nil
        }
        let allowed = mayRoam(c, base: base)
        if allowed, !mischiefWasAllowed {
            nextMischiefAt = max(nextMischiefAt, now.addingTimeInterval(randomDelay(Self.settleMischiefDelay)))
        }
        mischiefWasAllowed = allowed

        if var current = routine {
            if reaction != nil {
                // A real moment beats a game. It only starts at once where the
                // pet could be cut without a jump (`canCut`): straight home.
                routine = nil
                awayUntil = nil
                awayRequested = false
                dock = .home
                return
            }
            let stillAllowed = current.requested ? mayPlayOnRequest(c, base: base) : allowed
            if !stillAllowed, !current.windingUp, !c.isPetHovered {
                // Something needs the pet: finish this beat, then the quick way home.
                current.steps = Array(current.steps.prefix(current.index + 1)) + homeSteps(after: current.step)
                current.windingUp = true
            }
            while now >= current.stepEnd {
                guard current.index + 1 < current.steps.count else {
                    finish(current.steps[current.steps.count - 1], requested: current.requested, now: now)
                    return
                }
                current.stepStart = current.stepEnd
                current.index += 1
            }
            routine = current
            dock = current.step.dock
            return
        }

        guard reaction == nil else { return }
        if let request = requestedMischief, mayPlayOnRequest(c, base: base), flourish == nil || canCut(at: now) {
            requestedMischief = nil
            begin(request.kind, plan(request.kind, from: dock.side), now: now, requested: true)
            return
        }
        if dock.side == .left {
            // A visit that came from a request stays whatever the Mischief setting says.
            let wasRequested = awayRequested
            let leftAllowed = wasRequested ? mayPlayOnRequest(c, base: base) : allowed
            if !leftAllowed {
                // Something needs the pet: the quick way home, as soon as it can
                // be cut (a leap in progress lands first).
                if !c.isPetHovered, canCut(at: now) {
                    begin(.returnHome, crossing(from: .left), now: now, windingUp: true)
                }
            } else if flourish == nil, awayUntil.map({ now >= $0 }) ?? true {
                // The visit is over: home, playfully.
                begin(.returnHome, plan(.returnHome, from: .left), now: now, requested: wasRequested)
            }
            return
        }
        guard flourish == nil else { return }
        if allowed, now >= nextMischiefAt {
            let roll = rng.unit()
            let kind: PetMischief = roll < 0.45 ? .hideAndSeek : (roll < 0.8 ? .crossOver : .zoomies)
            begin(kind, plan(kind, from: .right), now: now)
        }
    }

    /// Starts a routine. `stepStart` lets a beat already under way keep its clock;
    /// `windingUp` marks a trip that is already the quick way home.
    private mutating func begin(_ kind: PetMischief, _ steps: [PetMischiefStep], now: Date, stepStart: Date? = nil,
                                windingUp: Bool = false, requested: Bool = false) {
        guard let first = steps.first else { return }
        routine = Routine(kind: kind, steps: steps, stepStart: stepStart ?? now, windingUp: windingUp, requested: requested)
        flourish = nil
        awayUntil = nil
        awayRequested = false
        dock = first.dock
    }

    /// Spotted mid-game. Never cuts a beat that is still moving: a dash or an arc
    /// lands first, a peek finishes sliding out before it pops, a wagging tail
    /// ducks back in and the pet comes out the front way. Returns whether the pet
    /// was caught (a pet inside the notch cannot be).
    private mutating func beginCaught(from current: Routine, now: Date) -> Bool {
        let step = current.step
        let side = step.dock.side
        let animation = step.animation.animation
        let elapsed = now.timeIntervalSince(current.stepStart)
        var steps: [PetMischiefStep] = []
        var start = now
        switch step.animation {
        case .tailPeek:
            steps = [
                beat(.duckTail, side, reach: step.dock.reach),
                beat(.hidden, side, duration: Self.growTime),
                beat(.dashOut, side),
            ]
        case .peek:
            let slideEnd = TimeInterval(animation.offsets.firstIndex { $0.dx == PetLayout.peekOffset } ?? 0) * animation.frameDuration
            if elapsed < slideEnd {
                steps.append(PetMischiefStep(animation: .peek, dock: step.dock, duration: slideEnd))
                start = current.stepStart
            }
            steps.append(beat(.popOut, side))
        default:
            guard step.animation.mischiefPose == .home else { return false }
            if now < current.stepEnd, animation.offset(at: elapsed) != .zero {
                steps.append(step)
                start = current.stepStart
            }
        }
        steps.append(beat(.caught, side))
        // A requested game stays requested when caught, so its visit on the left
        // still lasts whatever the Mischief setting says.
        begin(.caught, steps, now: now, stepStart: start, windingUp: true, requested: current.requested)
        return true
    }

    private mutating func finish(_ last: PetMischiefStep, requested: Bool = false, now: Date) {
        routine = nil
        dock = PetDock(side: last.dock.side, reach: PetLayout.idleDock)
        awayUntil = last.dock.side == .left ? now.addingTimeInterval(randomDelay(Self.awayStay)) : nil
        awayRequested = requested && last.dock.side == .left
        nextMischiefAt = now.addingTimeInterval(randomDelay(Self.mischiefDelay))
        nextFlourishAt = max(nextFlourishAt, now.addingTimeInterval(randomDelay(3...8)))
    }

    private func beat(_ animation: PetAnimationID, _ side: PetSide, reach: CGFloat = PetLayout.idleDock, duration: TimeInterval? = nil) -> PetMischiefStep {
        PetMischiefStep(animation: animation, dock: PetDock(side: side, reach: reach), duration: duration ?? animation.animation.duration)
    }

    private mutating func plan(_ kind: PetMischief, from side: PetSide) -> [PetMischiefStep] {
        switch kind {
        case .hideAndSeek:
            return hideAndSeek(from: side, peekingFrom: rng.unit() < 0.5 ? side : side.opposite)
        case .crossOver:
            return crossing(from: side)
        case .zoomies:
            return crossing(from: side) + crossing(from: side.opposite) + [beat(.pant, side)]
        case .returnHome:
            guard side == .left else { return [] }
            return rng.unit() < 0.35 ? hideAndSeek(from: .left, peekingFrom: .right) : crossing(from: .left)
        case .caught:
            return []
        }
    }

    /// Dash under the notch and out the other side. The dock only swaps sides
    /// while it is closed and the pet is hidden inside the notch.
    private func crossing(from side: PetSide) -> [PetMischiefStep] {
        let other = side.opposite
        return [
            beat(.dashIn, side),
            beat(.hidden, side, reach: 0, duration: Self.retractTime),
            beat(.hidden, other, reach: 0, duration: Self.switchTime),
            beat(.hidden, other, duration: Self.growTime),
            beat(.dashOut, other),
        ]
    }

    private mutating func hideAndSeek(from side: PetSide, peekingFrom peekSide: PetSide) -> [PetMischiefStep] {
        var steps = [
            beat(.sneakIn, side),
            beat(.hidden, side, reach: 0, duration: Self.retractTime),
            beat(.hidden, side, reach: 0, duration: randomDelay(1.0...2.2)),
        ]
        if rng.unit() < 0.4 {
            steps += [
                beat(.tailPeek, side, reach: PetLayout.peekReach),
                beat(.duckTail, side, reach: PetLayout.peekReach),
                beat(.hidden, side, reach: 0, duration: randomDelay(0.6...1.2)),
            ]
        }
        if peekSide != side {
            steps.append(beat(.hidden, peekSide, reach: 0, duration: Self.switchTime))
        }
        steps += [
            beat(.peek, peekSide, reach: PetLayout.peekReach),
            beat(.popOut, peekSide),
            beat(rng.unit() < 0.6 ? .blep : .snicker, peekSide),
        ]
        return steps
    }

    /// The quickest way home to the right of the notch from where `last` left
    /// the pet.
    private func homeSteps(after last: PetMischiefStep) -> [PetMischiefStep] {
        let side = last.dock.side
        switch last.animation.mischiefPose {
        case .home:
            return side == .right ? [] : crossing(from: .left)
        case .hidden:
            var steps: [PetMischiefStep] = []
            if side == .left {
                if last.dock.reach > 0 {
                    steps.append(beat(.hidden, .left, reach: 0, duration: Self.retractTime))
                }
                steps.append(beat(.hidden, .right, reach: 0, duration: Self.switchTime))
            }
            if side == .left || last.dock.reach < PetLayout.idleDock {
                steps.append(beat(.hidden, .right, duration: Self.growTime))
            }
            steps.append(beat(.dashOut, .right))
            return steps
        case .peeking:
            if last.animation == .tailPeek {
                // A tail goes back the way it came; the pet comes out the front.
                var steps = [beat(.duckTail, side, reach: last.dock.reach)]
                if side == .left {
                    steps.append(beat(.hidden, .left, reach: 0, duration: Self.retractTime))
                    steps.append(beat(.hidden, .right, reach: 0, duration: Self.switchTime))
                }
                return steps + [beat(.hidden, .right, duration: Self.growTime), beat(.dashOut, .right)]
            }
            if side == .right {
                return [beat(.popOut, .right)]
            }
            return [
                beat(.duck, .left, reach: last.dock.reach),
                beat(.hidden, .left, reach: 0, duration: Self.retractTime),
                beat(.hidden, .right, reach: 0, duration: Self.switchTime),
                beat(.hidden, .right, duration: Self.growTime),
                beat(.dashOut, .right),
            ]
        }
    }
}

/// A tiny deterministic random number generator (SplitMix64), so the pet's
/// "random" personality is reproducible in tests.
struct SplitMix64: Equatable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func index(_ count: Int) -> Int {
        Int(next() % UInt64(max(1, count)))
    }
}
