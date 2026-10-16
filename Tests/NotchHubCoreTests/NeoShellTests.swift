import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO's menu in Settings")
struct NeoShellTests {

    let ready = NeoShellStatus(app: true, accessibility: true, screenRecording: true, openAtLogin: true, version: "2.1.0", hotkey: "⌥⌘")

    @Test("a status is read from the core's object, and only from one that is NEO's")
    func statusPayload() {
        let payload: [String: Any] = [
            "running": true, "app": true, "accessibility": true, "screen_recording": false,
            "open_at_login": true, "version": "2.1.0", "hotkey": "⌘⇧Space",
        ]
        #expect(NeoShellStatus(payload: payload)
            == NeoShellStatus(app: true, accessibility: true, screenRecording: false, openAtLogin: true, version: "2.1.0", hotkey: "⌘⇧Space"))
        // Nothing reported (a core with no NEO.app): unknown, which is not "not allowed".
        let bare: [String: Any] = ["running": true, "app": false, "accessibility": NSNull(), "screen_recording": NSNull(), "version": NSNull()]
        #expect(NeoShellStatus(payload: bare) == NeoShellStatus())
        // Not the core's status object at all.
        #expect(NeoShellStatus(payload: ["accessibility": true]) == nil)
        #expect(NeoShellStatus(payload: [:]) == nil)
        // Words are kept short, and a wrong type is no answer.
        let odd: [String: Any] = ["running": true, "app": true, "accessibility": "yes", "version": String(repeating: "9", count: 99), "hotkey": ""]
        let parsed = NeoShellStatus(payload: odd)
        #expect(parsed?.accessibility == nil && parsed?.version?.count == 32 && parsed?.hotkey == nil)
    }

    @Test("each action is one shell command, by NEO's own names")
    func commands() {
        #expect(NeoShellAction.show.command == #"{"cmd":"shell","action":"show"}"#)
        #expect(NeoShellAction.settings.command == #"{"cmd":"shell","action":"settings"}"#)
        #expect(NeoShellAction.restart.command == #"{"cmd":"shell","action":"restart"}"#)
        #expect(NeoShellAction.openLogs.command == #"{"cmd":"shell","action":"open_logs"}"#)
        #expect(NeoShellAction.eraseMemory.command == #"{"cmd":"shell","action":"erase_memory"}"#)
        #expect(NeoShellAction.openAtLogin(true).command == #"{"cmd":"shell","action":"open_at_login","on":true}"#)
        #expect(NeoShellAction.openAtLogin(false).command == #"{"cmd":"shell","action":"open_at_login","on":false}"#)
        #expect(NeoShellAction.quit.command == #"{"cmd":"shell","action":"quit"}"#)
        // Every one is valid JSON carrying nothing but the command.
        for action in [NeoShellAction.show, .settings, .restart, .openLogs, .eraseMemory, .openAtLogin(true), .quit] {
            let object = try? JSONSerialization.jsonObject(with: Data(action.command.utf8)) as? [String: Any]
            #expect(object?["cmd"] as? String == "shell" && object?["action"] as? String == action.name)
            let keys = Set((object ?? [:]).keys)
            #expect(keys.isSubset(of: ["cmd", "action", "on"]))
        }
    }

    @Test("an intent is NEO.app's to do, or the host's own")
    func intents() {
        #expect(NeoSettingsIntent.apiKeys.shellAction == .settings)
        #expect(NeoSettingsIntent.openLogs.shellAction == .openLogs)
        #expect(NeoSettingsIntent.restart.shellAction == .restart)
        #expect(NeoSettingsIntent.eraseMemory.shellAction == .eraseMemory)
        #expect(NeoSettingsIntent.openAtLogin(false).shellAction == .openAtLogin(false))
        #expect(NeoSettingsIntent.quit.shellAction == .quit)
        // The host opens its own panel, launches NEO.app and opens System Settings itself.
        #expect(NeoSettingsIntent.openChat.shellAction == nil)
        #expect(NeoSettingsIntent.start.shellAction == nil)
        #expect(NeoSettingsIntent.openPermission(.accessibility).shellAction == nil)
        #expect(NeoPermission.accessibility.settingsURL.hasSuffix("?Privacy_Accessibility"))
        #expect(NeoPermission.screenRecording.settingsURL.hasSuffix("?Privacy_ScreenCapture"))
    }

    @Test("“Listen for Neo” is one set command, with a real boolean")
    func settingCommand() {
        #expect(NeoSetting.wakeWord(false).command == #"{"cmd":"set","name":"wake_word","value":false}"#)
        #expect(NeoSetting.wakeWord(true).command == #"{"cmd":"set","name":"wake_word","value":true}"#)
        for on in [true, false] {
            let setting = NeoSetting.wakeWord(on)
            let object = try? JSONSerialization.jsonObject(with: Data(setting.command.utf8)) as? [String: Any]
            #expect(Set((object ?? [:]).keys) == ["cmd", "name", "value"])
            #expect(object?["cmd"] as? String == "set" && object?["name"] as? String == setting.name)
            #expect(NeoCoreSettings(payload: ["wake_word": object?["value"] as Any]).wakeWord == on) // a JSON boolean, as the core requires
        }
        // The intent that asks for it is the core's to do — not NEO.app's shell's.
        #expect(NeoSettingsIntent.wakeWord(false).setting == .wakeWord(false))
        #expect(NeoSettingsIntent.wakeWord(true).shellAction == nil)
        for intent in [NeoSettingsIntent.openChat, .apiKeys, .restart, .openAtLogin(true), .quit, .start, .openPermission(.accessibility)] {
            #expect(intent.setting == nil, "\(intent)")
        }
    }

    @Test("the core's settings are read from its object: a boolean, or nothing")
    func corePayload() {
        #expect(NeoCoreSettings(payload: ["wake_word": true]) == NeoCoreSettings(wakeWord: true))
        #expect(NeoCoreSettings(payload: ["wake_word": false, "state": "idle"]) == NeoCoreSettings(wakeWord: false))
        #expect(NeoCoreSettings(payload: [:]) == NeoCoreSettings())
        for odd in ["false", 0, 1, NSNull(), ["on": true]] as [Any] {
            #expect(NeoCoreSettings(payload: ["wake_word": odd]).wakeWord == nil, "\(odd)")
        }
    }

    @Test("“Listen for Neo” shows what the core said, with what it means for the microphone — and dims when there is no core to ask")
    func wakeWord() {
        // On: the microphone stays open for the wake word.
        let on = NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings(wakeWord: true))
        #expect(on.wakeWord == true && on.listensForNeo)
        #expect(on.wakeWordCaption == "The microphone stays on to hear “Neo”.")
        #expect(on.isEnabled(.wakeWord(false)))
        // Off: the keys summon NEO, and the caption names the ones that do right now.
        let off = NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings(wakeWord: false))
        #expect(off.wakeWord == false && !off.listensForNeo)
        #expect(off.wakeWordCaption == "Summon with ⌥⌘ — the microphone is on only while NEO listens.")
        #expect(off.isEnabled(.wakeWord(true)))
        var fallback = ready
        fallback.hotkey = "⌘⇧Space" // before Accessibility is allowed
        #expect(NeoSettingsModel(featureOn: true, connected: true, shell: fallback, core: NeoCoreSettings(wakeWord: false)).wakeWordCaption
            == "Summon with ⌘⇧Space — the microphone is on only while NEO listens.")
        // It is the core's setting: a core with no NEO.app behind it switches it too.
        let coreOnly = NeoSettingsModel(featureOn: true, connected: true, shell: nil, core: NeoCoreSettings(wakeWord: false))
        #expect(coreOnly.availability == .coreOnly && coreOnly.isEnabled(.wakeWord(true)) && !coreOnly.listensForNeo)
        #expect(coreOnly.wakeWordCaption.hasPrefix("Summon with \(NeoSettingsModel.defaultHotkey) —"))
        // NEO not running, the feature off, or a core too old to say: the row
        // stays, dimmed, on the side NEO starts with — what was said before
        // NEO quit says nothing now.
        let stale = NeoCoreSettings(wakeWord: false)
        for model in [
            NeoSettingsModel(featureOn: true, connected: false, shell: ready, core: stale),
            NeoSettingsModel(featureOn: false, connected: true, shell: ready, core: stale),
            NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings()),
            NeoSettingsModel(featureOn: true, connected: true, shell: ready),
        ] {
            #expect(model.wakeWord == nil && model.listensForNeo, "\(model.availability)")
            #expect(!model.isEnabled(.wakeWord(false)) && !model.isEnabled(.wakeWord(true)), "\(model.availability)")
            #expect(model.wakeWordCaption == "The microphone stays on to hear “Neo”.")
        }
    }

    @Test("“Gentle check-ins” is the core's setting like the wake word: off unless the core says on, dimmed when nobody can say")
    func wellbeingCheckins() {
        // One set command with a real boolean, read back the way the core says it.
        for on in [true, false] {
            let setting = NeoSetting.wellbeingCheckins(on)
            #expect(setting.name == "wellbeing_checkins")
            let object = try? JSONSerialization.jsonObject(with: Data(setting.command.utf8)) as? [String: Any]
            #expect(Set((object ?? [:]).keys) == ["cmd", "name", "value"])
            #expect(object?["cmd"] as? String == "set" && object?["name"] as? String == "wellbeing_checkins")
            #expect(NeoCoreSettings(payload: ["wellbeing_checkins": object?["value"] as Any]).wellbeingCheckins == on)
            // The intent is the core's to do, not NEO.app's shell's.
            #expect(NeoSettingsIntent.wellbeingCheckins(on).setting == .wellbeingCheckins(on))
            #expect(NeoSettingsIntent.wellbeingCheckins(on).shellAction == nil)
        }
        for odd in ["true", 0, 1, NSNull()] as [Any] {
            #expect(NeoCoreSettings(payload: ["wellbeing_checkins": odd]).wellbeingCheckins == nil, "\(odd)")
        }
        // The two settings are read apart.
        #expect(NeoCoreSettings(payload: ["wake_word": true, "wellbeing_checkins": false]) == NeoCoreSettings(wakeWord: true, wellbeingCheckins: false))

        let on = NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings(wellbeingCheckins: true))
        #expect(on.wellbeingCheckins == true && on.checkinsForSounds && on.isEnabled(.wellbeingCheckins(false)))
        let off = NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings(wellbeingCheckins: false))
        #expect(off.wellbeingCheckins == false && !off.checkinsForSounds && off.isEnabled(.wellbeingCheckins(true)))
        // Honest about what leaves the Mac.
        #expect(on.wellbeingCheckinsCaption.contains("on-device") && on.wellbeingCheckinsCaption.contains("Gemini"))
        // NEO not running, the feature off, or a core too old to say: off, and dimmed.
        for model in [
            NeoSettingsModel(featureOn: true, connected: false, shell: ready, core: NeoCoreSettings(wellbeingCheckins: true)),
            NeoSettingsModel(featureOn: false, connected: true, shell: ready, core: NeoCoreSettings(wellbeingCheckins: true)),
            NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings(wakeWord: true)),
        ] {
            #expect(model.wellbeingCheckins == nil && !model.checkinsForSounds, "\(model.availability)")
            #expect(!model.isEnabled(.wellbeingCheckins(true)) && !model.isEnabled(.wellbeingCheckins(false)), "\(model.availability)")
        }
    }

    @Test("NEO running, everything allowed: every row works, and nothing asks to be allowed or started")
    func readyModel() {
        let model = NeoSettingsModel(featureOn: true, connected: true, shell: ready)
        #expect(model.availability == .ready && model.isRunning)
        #expect(model.runningLabel == "Running" && model.subtitle == "NEO 2.1.0 is running")
        #expect(model.accessibility == .allowed && model.screenRecording == .allowed)
        #expect(model.accessibility.label == "Allowed ✓")
        #expect(model.openAtLogin == true && model.hotkey == "⌥⌘")
        for intent in [NeoSettingsIntent.openChat, .apiKeys, .openLogs, .restart, .eraseMemory, .openAtLogin(false), .quit] {
            #expect(model.isEnabled(intent), "\(intent)")
        }
        #expect(!model.canStart && !model.isEnabled(.start))
        #expect(!model.isEnabled(.openPermission(.accessibility)) && !model.isEnabled(.openPermission(.screenRecording)))
    }

    @Test("a permission NEO.app lacks says so, with a way to the right pane — and only that one")
    func missingPermission() {
        var status = ready
        status.screenRecording = false
        status.hotkey = "⌘⇧Space"
        let model = NeoSettingsModel(featureOn: true, connected: true, shell: status)
        #expect(model.screenRecording == .notAllowed && model.screenRecording.label == "Not allowed")
        #expect(model.isEnabled(.openPermission(.screenRecording)))
        #expect(!model.isEnabled(.openPermission(.accessibility)))
        #expect(model.hotkey == "⌘⇧Space") // what NEO.app says summons it right now
        #expect(model.isEnabled(.restart))
    }

    @Test("NEO not running: the rows stay, dimmed, and Start NEO is offered")
    func away() {
        // What its shell said before it quit is not what is true now.
        let model = NeoSettingsModel(featureOn: true, connected: false, shell: ready)
        #expect(model.availability == .away && !model.isRunning)
        #expect(model.runningLabel == "Not running" && model.subtitle == "NEO isn't running")
        #expect(model.accessibility == .unknown && model.screenRecording == .unknown && model.accessibility.label == "—")
        #expect(model.openAtLogin == nil && model.version == nil && model.hotkey == NeoSettingsModel.defaultHotkey)
        for intent in [NeoSettingsIntent.openChat, .apiKeys, .openLogs, .restart, .eraseMemory, .openAtLogin(true), .quit,
                       .openPermission(.accessibility), .openPermission(.screenRecording)] {
            #expect(!model.isEnabled(intent), "\(intent)")
        }
        #expect(model.canStart && model.isEnabled(.start))
        #expect(NeoSettingsModel.appPath == "/Applications/NEO.app")
    }

    @Test("the feature off: nothing works but its switch, and NEO is not started behind the user's back")
    func off() {
        for connected in [false, true] {
            let model = NeoSettingsModel(featureOn: false, connected: connected, shell: ready)
            #expect(model.availability == .off && !model.isRunning)
            #expect(model.runningLabel == "Off in the notch")
            #expect(!model.canStart && !model.isEnabled(.start) && !model.isEnabled(.openChat) && !model.isEnabled(.quit))
            #expect(model.accessibility == .unknown)
        }
    }

    @Test("a core with no NEO.app behind it: the chat works, the menu's actions have nobody to do them")
    func coreOnly() {
        for shell in [nil, NeoShellStatus()] as [NeoShellStatus?] {
            let model = NeoSettingsModel(featureOn: true, connected: true, shell: shell)
            #expect(model.availability == .coreOnly && model.isRunning)
            #expect(model.runningLabel == "Running")
            #expect(model.isEnabled(.openChat))
            for intent in [NeoSettingsIntent.apiKeys, .openLogs, .restart, .eraseMemory, .openAtLogin(true), .quit, .start] {
                #expect(!model.isEnabled(intent), "\(intent)")
            }
            #expect(model.accessibility == .unknown && !model.isEnabled(.openPermission(.accessibility)))
        }
    }

    // MARK: - Brains & Keys

    /// NEO's `brains` summary as its core sends it (neo2/core/brains.py): each
    /// role an object, which providers have a key, and nothing else.
    static let readyBrains: [String: Any] = [
        "ready": true,
        "brain": ["ref": "claude@claude-opus-5-5", "provider": "anthropic", "label": "Claude Opus 5.5", "ok": true],
        "quick": ["ref": "claude@claude-haiku-5-5", "provider": "anthropic", "label": "Claude Haiku 5.5", "ok": true],
        "eyes": NSNull(),
        "voice": "live",
        "providers": ["gemini": true, "anthropic": true, "openai": false, "custom:lab": false],
        "restart_needed": false,
    ]

    @Test("NEO's brains are read from the core's object: whether NEO has a model, and each role by name — nothing else is kept")
    func brainPayload() throws {
        let status = try #require(NeoBrainStatus(payload: Self.readyBrains))
        #expect(status == NeoBrainStatus(
            ready: true, brain: "Claude Opus 5.5", quick: "Claude Haiku 5.5", eyes: nil, brainOK: true, voice: "live", restartNeeded: false
        ))
        // Which providers have a key, each role's reference: not read, not kept.
        let kept = Set(Mirror(reflecting: status).children.compactMap(\.label))
        #expect(kept == ["ready", "brain", "quick", "eyes", "brainOK", "voice", "restartNeeded"])

        // Nothing set up yet, a restart waiting, and an Eyes brain of its own.
        let waiting: [String: Any] = [
            "ready": false,
            "brain": ["label": "Gemini 3.8 Flash", "ok": false],
            "quick": ["label": "Gemini 3.8 Flash", "ok": false],
            "eyes": ["label": "GPT-6 Luna", "ok": false],
            "voice": "local", "restart_needed": true, "added_later": ["x": 1],
        ]
        #expect(NeoBrainStatus(payload: waiting) == NeoBrainStatus(
            ready: false, brain: "Gemini 3.8 Flash", quick: "Gemini 3.8 Flash", eyes: "GPT-6 Luna", brainOK: false, voice: "local", restartNeeded: true
        ))
        // A role may be plain text: then nobody said whether it answers.
        #expect(NeoBrainStatus(payload: ["ready": true, "brain": "Claude Opus 5.5"]) == NeoBrainStatus(ready: true, brain: "Claude Opus 5.5"))
        // The least NEO's object says: whether NEO is ready.
        #expect(NeoBrainStatus(payload: ["ready": false]) == NeoBrainStatus(ready: false))
    }

    @Test("a brains object that does not say, with a real boolean, whether NEO is ready is not NEO's")
    func brainPayloadNotNeos() {
        #expect(NeoBrainStatus(payload: [:]) == nil)
        #expect(NeoBrainStatus(payload: ["brain": ["label": "Claude Opus 5.5", "ok": true]]) == nil)
        for odd in ["true", 1, 0, NSNull(), ["ok": true]] as [Any] {
            #expect(NeoBrainStatus(payload: ["ready": odd, "brain": "Claude Opus 5.5"]) == nil, "\(odd)")
        }
        // Inside one of NEO's, a wrong type is no answer.
        let odd: [String: Any] = [
            "ready": true, "brain": ["label": 42, "ok": "yes"], "quick": 7, "eyes": ["ok": true],
            "voice": false, "restart_needed": "true",
        ]
        #expect(NeoBrainStatus(payload: odd) == NeoBrainStatus(ready: true))
        #expect(NeoBrainStatus(payload: ["ready": true, "restart_needed": 1])?.restartNeeded == false)
    }

    @Test("a brain's name is kept to one short line")
    func brainLabels() {
        let long = String(repeating: "m", count: 99)
        let parsed = NeoBrainStatus(payload: [
            "ready": true, "brain": ["label": long], "quick": long, "eyes": ["label": "  \n "],
            "voice": String(repeating: "v", count: 40),
        ])
        #expect(parsed?.brain?.count == NeoBrainStatus.labelLimit && parsed?.quick?.count == NeoBrainStatus.labelLimit)
        #expect(parsed?.eyes == nil) // nothing but blanks is no name
        #expect(parsed?.voice?.count == 16)
        // A line break (or any control character) is a space; the ends are trimmed.
        let broken = NeoBrainStatus(payload: ["ready": true, "brain": ["label": " Claude\nOpus\t5.5\u{7} "]])
        #expect(broken?.brain == "Claude Opus 5.5")
        // Cut at the limit, never leaving a trailing space.
        let spaced = String(repeating: "a", count: NeoBrainStatus.labelLimit - 1) + " tail"
        #expect(NeoBrainStatus(payload: ["ready": true, "brain": spaced])?.brain == String(repeating: "a", count: NeoBrainStatus.labelLimit - 1))
        // Names the core sends are kept whole: a middle dot, an accent.
        let endpoint = "DeepSeek · deepseek-v4-pro"
        #expect(NeoBrainStatus(payload: ["ready": true, "brain": ["label": endpoint]])?.brain == endpoint)
    }

    @Test("the Brain row: the model that does NEO's tasks, lit while NEO has one — and no “Set up…”")
    func brainRowReady() throws {
        let status = try #require(NeoBrainStatus(payload: Self.readyBrains))
        let model = NeoSettingsModel(featureOn: true, connected: true, shell: ready, brain: status)
        #expect(model.brain == status && model.showsBrain)
        #expect(model.brainLabel == "Claude Opus 5.5" && model.brainIsGood && !model.offersBrainSetup)
        // A NEO that is ready but named no brain still says so.
        let unnamed = NeoSettingsModel(featureOn: true, connected: true, shell: ready, brain: NeoBrainStatus(ready: true))
        #expect(unnamed.brainLabel == "Ready" && unnamed.brainIsGood)
        // Ready (a backup answers), but the chosen brain cannot (its key was
        // refused): its name, not lit — NEO's chat says what is wrong.
        let refused = NeoBrainStatus(ready: true, brain: "Claude Opus 5.5", brainOK: false)
        let dim = NeoSettingsModel(featureOn: true, connected: true, shell: ready, brain: refused)
        #expect(dim.brainLabel == "Claude Opus 5.5" && !dim.brainIsGood && !dim.offersBrainSetup)
        // The rest of the section is as it was.
        #expect(model.availability == .ready && model.isEnabled(.apiKeys))
        #expect(model == NeoSettingsModel(featureOn: true, connected: true, shell: ready, brain: status, showsTimers: true))
    }

    @Test("no brain yet: “Not set up”, and “Set up…” opens NEO.app's Brains & Keys window — the same intent as the Actions row")
    func brainRowNotSetUp() {
        let none = NeoBrainStatus(ready: false, brain: "Gemini 3.8 Flash", brainOK: false, voice: "local")
        let model = NeoSettingsModel(featureOn: true, connected: true, shell: ready, brain: none)
        #expect(model.showsBrain && model.brainLabel == "Not set up" && !model.brainIsGood)
        #expect(model.offersBrainSetup && model.isEnabled(.apiKeys))
        // It asks NEO.app's shell for its settings action: no new command.
        #expect(NeoSettingsIntent.apiKeys.shellAction == .settings)
        #expect(NeoSettingsIntent.apiKeys.shellAction?.command == #"{"cmd":"shell","action":"settings"}"#)
        // A core run by hand has no NEO.app, so no window to open: no button.
        let byHand = NeoSettingsModel(featureOn: true, connected: true, shell: NeoShellStatus(), brain: none)
        #expect(byHand.availability == .coreOnly && byHand.brainLabel == "Not set up")
        #expect(!byHand.offersBrainSetup && !byHand.isEnabled(.apiKeys))
    }

    @Test("NEO away or off: the Brain row stays, dimmed, and says nothing stale; a core too old to report brains has none")
    func brainRowUnknown() {
        let stale = NeoBrainStatus(ready: true, brain: "Claude Opus 5.5", brainOK: true)
        for model in [
            NeoSettingsModel(featureOn: true, connected: false, shell: ready, brain: stale),
            NeoSettingsModel(featureOn: false, connected: true, shell: ready, brain: stale),
            NeoSettingsModel(featureOn: false, connected: false, shell: nil),
        ] {
            #expect(model.brain == nil && model.showsBrain, "\(model.availability)")
            #expect(model.brainLabel == "—" && !model.brainIsGood && !model.offersBrainSetup, "\(model.availability)")
        }
        // Connected to a NEO that sends no brains (from before Brains & Keys):
        // no Brain row at all — every call made before it existed included.
        for model in [
            NeoSettingsModel(featureOn: true, connected: true, shell: ready),
            NeoSettingsModel(featureOn: true, connected: true, shell: ready, core: NeoCoreSettings(wakeWord: true), showsTimers: false),
            NeoSettingsModel(featureOn: true, connected: true, shell: nil),
        ] {
            #expect(model.brain == nil && !model.showsBrain, "\(model.availability)")
            #expect(!model.offersBrainSetup, "\(model.availability)")
        }
    }

    @Test("the foot of the section says why the rows are dim")
    func footnotes() {
        #expect(NeoSettingsModel(featureOn: false, connected: false, shell: nil).footnote == "Turn NEO on to use these")
        #expect(NeoSettingsModel(featureOn: true, connected: false, shell: nil).footnote == "Start NEO to use these")
        #expect(NeoSettingsModel(featureOn: true, connected: true, shell: nil).footnote.contains("NEO.app"))
        #expect(NeoSettingsModel(featureOn: true, connected: true, shell: ready).footnote.contains("in the notch"))
    }
}
