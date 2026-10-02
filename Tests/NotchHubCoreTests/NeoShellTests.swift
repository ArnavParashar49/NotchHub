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

    @Test("the foot of the section says why the rows are dim")
    func footnotes() {
        #expect(NeoSettingsModel(featureOn: false, connected: false, shell: nil).footnote == "Turn NEO on to use these")
        #expect(NeoSettingsModel(featureOn: true, connected: false, shell: nil).footnote == "Start NEO to use these")
        #expect(NeoSettingsModel(featureOn: true, connected: true, shell: nil).footnote.contains("NEO.app"))
        #expect(NeoSettingsModel(featureOn: true, connected: true, shell: ready).footnote.contains("in the notch"))
    }
}
