import Foundation
import Testing
import WebKit
import NotchHubCore
@testable import NotchHubSystem

@Suite("NeoListener parsing")
struct NeoListenerParsingTests {

    @Test("a hello yields NEO's state and nothing from the replay")
    func hello() {
        let text = #"{"type":"hello","data":{"state":"listening","recent":[{"type":"transcript","data":{"role":"assistant","text":"old","final":true},"ts":1}],"confirm":null,"problems":[]},"ts":2}"#
        #expect(NeoListener.facts(in: text) == [.state(.listening)])
    }

    @Test("state, transcript, note and error are facts; the rest is not")
    func messages() {
        #expect(NeoListener.facts(in: #"{"type":"state","data":{"state":"speaking","job":"j1"},"ts":1}"#) == [.state(.speaking)])
        #expect(NeoListener.facts(in: #"{"type":"transcript","data":{"role":"user","text":"hi","final":false,"job":""},"ts":1}"#)
            == [.transcript(role: .user, text: "hi", final: false)])
        #expect(NeoListener.facts(in: #"{"type":"note","data":{"text":"n"},"ts":1}"#) == [.note("n")])
        #expect(NeoListener.facts(in: #"{"type":"error","data":{"message":"m"},"ts":1}"#) == [.error("m")])
        for other in ["browser_state", "tool_start", "tool_end", "turn", "confirm", "problems", "erased", "ui_host", "shell", "shell_status", "shell_result", "host_attached", "settings", "set_result"] {
            #expect(NeoListener.facts(in: #"{"type":"\#(other)","data":{"state":"speaking"},"ts":1}"#).isEmpty, "\(other)")
        }
    }

    @Test("camera state carries normalized detection boxes to NEO's camera surface")
    func cameraBoxes() {
        let message = #"{"type":"camera_state","data":{"sid":"cam-1","status":"analysing","labels":["person"],"boxes":[{"id":7,"x":0.1,"y":0.2,"w":0.5,"h":0.4,"label":"person","score":0.93},{"x":0.9,"y":0.9,"w":0.4,"h":0.4,"label":"edge","score":1.4},{"x":0.2,"y":0.2,"w":-1,"h":0.1,"label":"invalid"}]},"ts":1}"#
        let facts = NeoListener.facts(in: message)
        #expect(facts.count == 1)
        guard case let .cameraCard(card) = facts.first else { return }
        #expect(card.sid == "cam-1")
        #expect(card.status == "analysing")
        #expect(card.labels == ["person"])
        #expect(card.boxes.count == 2)
        #expect(card.boxes.first == NeoCameraBox(id: 7, x: 0.1, y: 0.2, w: 0.5, h: 0.4, label: "person", score: 0.93))
        #expect(card.boxes.last?.id == 1)
        #expect(abs((card.boxes.last?.w ?? 0) - 0.1) < 0.000001)
        #expect(abs((card.boxes.last?.h ?? 0) - 0.1) < 0.000001)
        #expect(card.boxes.last?.score == 1)
    }

    @Test("what NEO.app's shell reported is read from the hello and from shell_status, and from nothing else")
    func shellStatus() {
        let shell = #"{"running":true,"app":true,"accessibility":true,"screen_recording":false,"open_at_login":true,"version":"2.1.0","hotkey":"⌥⌘"}"#
        let expected = NeoShellStatus(app: true, accessibility: true, screenRecording: false, openAtLogin: true, version: "2.1.0", hotkey: "⌥⌘")
        #expect(NeoListener.shellStatus(in: #"{"type":"hello","data":{"state":"idle","recent":[],"shell":\#(shell)},"ts":1}"#) == expected)
        #expect(NeoListener.shellStatus(in: #"{"type":"shell_status","data":\#(shell),"ts":1}"#) == expected)
        // A core run by hand: it answers, but no NEO.app stands behind it.
        let bare = #"{"running":true,"app":false,"accessibility":null,"screen_recording":null,"open_at_login":null,"version":null,"hotkey":null}"#
        #expect(NeoListener.shellStatus(in: #"{"type":"shell_status","data":\#(bare),"ts":1}"#) == NeoShellStatus())
        // An older core's hello has none; a host's own answers and requests are not a status.
        #expect(NeoListener.shellStatus(in: #"{"type":"hello","data":{"state":"idle","recent":[]},"ts":1}"#) == nil)
        #expect(NeoListener.shellStatus(in: #"{"type":"shell_status","data":{"accessibility":true},"ts":1}"#) == nil)
        for other in ["shell", "shell_result", "state", "host_attached"] {
            #expect(NeoListener.shellStatus(in: #"{"type":"\#(other)","data":\#(shell),"ts":1}"#) == nil, "\(other)")
        }
        #expect(NeoListener.shellStatus(in: "not json") == nil)
    }

    @Test("where “Listen for Neo” stands is read from the hello and from a settings event, and from nothing else")
    func coreSettings() {
        // The hello says it; a settings event says it again whenever it is switched.
        #expect(NeoListener.coreSettings(in: #"{"type":"hello","data":{"state":"idle","recent":[],"wake_word":true},"ts":1}"#) == NeoCoreSettings(wakeWord: true))
        #expect(NeoListener.coreSettings(in: #"{"type":"hello","data":{"state":"idle","recent":[],"wake_word":false},"ts":1}"#) == NeoCoreSettings(wakeWord: false))
        #expect(NeoListener.coreSettings(in: #"{"type":"settings","data":{"wake_word":false},"ts":1}"#) == NeoCoreSettings(wakeWord: false))
        #expect(NeoListener.coreSettings(in: #"{"type":"settings","data":{"wake_word":true},"ts":1}"#) == NeoCoreSettings(wakeWord: true))
        // An older core's hello has no such setting: "unknown" — said, so that
        // what an earlier connection reported does not linger.
        #expect(NeoListener.coreSettings(in: #"{"type":"hello","data":{"state":"idle","recent":[]},"ts":1}"#) == NeoCoreSettings(wakeWord: nil))
        // Only a real boolean is an answer.
        for odd in [#""false""#, "0", "1", "null", #"{"on":true}"#] {
            #expect(NeoListener.coreSettings(in: #"{"type":"hello","data":{"state":"idle","wake_word":\#(odd)},"ts":1}"#) == NeoCoreSettings(wakeWord: nil), "\(odd)")
            #expect(NeoListener.coreSettings(in: #"{"type":"settings","data":{"wake_word":\#(odd)},"ts":1}"#) == nil, "\(odd)")
        }
        // A settings event about something else, the answer to a host's own
        // request, and every other message: not where the switch stands.
        #expect(NeoListener.coreSettings(in: #"{"type":"settings","data":{"listen_timeout_s":7},"ts":1}"#) == nil)
        for other in ["set_result", "set", "state", "shell_status", "ui_host"] {
            #expect(NeoListener.coreSettings(in: #"{"type":"\#(other)","data":{"wake_word":false,"name":"wake_word","ok":true},"ts":1}"#) == nil, "\(other)")
        }
        #expect(NeoListener.coreSettings(in: "not json") == nil)
    }

    @Test("a confirmation staged, pending in the hello, or over is a fact for the island's Allow / Cancel")
    func confirmations() {
        let card = #"{"action_id":"trash:4d15b0099e5a9d0a","tool":"trash","summary":"move report.pdf to the Trash","detail":"/Users/me/Documents/report.pdf","scopes":[],"app":""}"#
        let expected = NeoConfirmCard(actionID: "trash:4d15b0099e5a9d0a", tool: "trash", summary: "move report.pdf to the Trash", detail: "/Users/me/Documents/report.pdf")
        #expect(NeoListener.facts(in: #"{"type":"confirm","data":\#(card),"ts":1}"#) == [.confirm(expected)])
        // A question still waiting when NotchHub connects: in the hello, after NEO's state.
        #expect(NeoListener.facts(in: #"{"type":"hello","data":{"state":"confirming","recent":[],"confirm":\#(card)},"ts":1}"#)
            == [.state(.confirming), .confirm(expected)])
        #expect(NeoListener.facts(in: #"{"type":"hello","data":{"state":"idle","recent":[],"confirm":null},"ts":1}"#) == [.state(.idle)])
        // Answered (anywhere), superseded or expired.
        for outcome in ["confirmed", "user cancelled", "superseded", "expired"] {
            #expect(NeoListener.facts(in: #"{"type":"confirm_done","data":{"action_id":"trash:4d15b0099e5a9d0a","outcome":"\#(outcome)"},"ts":1}"#)
                == [.confirmDone("trash:4d15b0099e5a9d0a")], "\(outcome)")
        }
        // Nothing an answer could name: no buttons.
        #expect(NeoListener.facts(in: #"{"type":"confirm","data":{"tool":"trash","summary":"x"},"ts":1}"#).isEmpty)
        #expect(NeoListener.facts(in: #"{"type":"confirm","data":{"action_id":"","summary":"x"},"ts":1}"#).isEmpty)
        #expect(NeoListener.facts(in: #"{"type":"confirm_done","data":{"outcome":"expired"},"ts":1}"#).isEmpty)
        // A script's newlines never reach the card as layout: one plain line.
        let script = #"{"type":"confirm","data":{"action_id":"shell:1","tool":"shell","summary":"run a command","detail":"cd /tmp\n  rm -rf x"},"ts":1}"#
        #expect(NeoListener.facts(in: script) == [.confirm(NeoConfirmCard(actionID: "shell:1", tool: "shell", summary: "run a command", detail: "cd /tmp rm -rf x"))])
    }

    @Test("a card's opening and closing are facts for the panel")
    func cards() {
        #expect(NeoListener.facts(in: #"{"type":"browser_open","data":{"sid":"s","job":"j"},"ts":1}"#) == [.card(.browser, open: true)])
        #expect(NeoListener.facts(in: #"{"type":"browser_close","data":{"sid":"s","reason":"done"},"ts":1}"#) == [.card(.browser, open: false)])
        // The camera's session first (its "starting", which NEO says next
        // anyway), then the opening: the island knows which one it shows.
        #expect(NeoListener.facts(in: #"{"type":"camera_open","data":{"sid":"c","reason":"look"},"ts":1}"#)
            == [.cameraCard(NeoCameraCardState(sid: "c", status: "starting")), .card(.camera, open: true)])
        #expect(NeoListener.facts(in: #"{"type":"camera_open","data":{},"ts":1}"#) == [.card(.camera, open: true)])
        #expect(NeoListener.facts(in: #"{"type":"camera_close","data":{"sid":"c","reason":"stopped"},"ts":1}"#) == [.card(.camera, open: false)])
        #expect(NeoListener.facts(in: #"{"type":"song_open","data":{"sid":"m"},"ts":1}"#) == [
            .songCard(NeoSongCardState(sid: "m", status: "listening")),
            .card(.song, open: true),
        ])
        #expect(NeoListener.facts(in: #"{"type":"song_close","data":{"sid":"m"},"ts":1}"#) == [.card(.song, open: false)])
    }

    @Test("a camera already on when NotchHub connects comes back from the hello: its state, then its opening")
    func helloCameraLive() {
        let live = #"{"sid":"cam-9","status":"analysing","labels":["mug"],"boxes":[{"id":1,"x":0.1,"y":0.1,"w":0.2,"h":0.2,"label":"mug","score":0.8}],"popout":false,"reason":"look"}"#
        let facts = NeoListener.facts(in: #"{"type":"hello","data":{"state":"thinking","recent":[],"camera":{"live":\#(live)}},"ts":1}"#)
        #expect(facts == [
            .state(.thinking),
            .cameraCard(NeoCameraCardState(sid: "cam-9", status: "analysing", labels: ["mug"],
                                           boxes: [NeoCameraBox(id: 1, x: 0.1, y: 0.1, w: 0.2, h: 0.2, label: "mug", score: 0.8)])),
            .card(.camera, open: true),
        ])
        // Off, or a hello from a core without a camera: nothing to recover.
        #expect(NeoListener.facts(in: #"{"type":"hello","data":{"state":"idle","recent":[],"camera":{"live":null}},"ts":1}"#) == [.state(.idle)])
        #expect(NeoListener.facts(in: #"{"type":"hello","data":{"state":"idle","recent":[],"camera":{"live":{"status":"live"}}},"ts":1}"#) == [.state(.idle)])
    }

    @Test("closing NEO's camera here stops that session by name, so a late stop never ends a newer one")
    func cameraStopNamesTheSession() throws {
        let named = NeoListener.cameraStopCommand(sid: "Ab-_09")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(named.utf8)) as? [String: String])
        #expect(object == ["cmd": "camera_stop", "sid": "Ab-_09"])
        #expect(NeoListener.cameraStopCommand(sid: nil) == NeoListener.cameraStopCommand)
        #expect(NeoListener.cameraStopCommand(sid: "") == NeoListener.cameraStopCommand)
    }

    @Test("a song's state: its result trimmed, a null year is no year, and only a modest image data URI is a cover")
    func songState() throws {
        func song(_ result: String) -> NeoSongCardState? {
            let facts = NeoListener.facts(in: #"{"type":"song_state","data":{"sid":"m1","status":"found","level":1.7,"elapsed_s":-3,"result":\#(result)},"ts":1}"#)
            guard case let .songCard(state)? = facts.first, facts.count == 1 else { return nil }
            return state
        }
        let found = try #require(song(#"{"title":"Midnight City","artist":"M83","album":"Hurry Up, We're Dreaming","year":"2011"}"#))
        #expect(found.sid == "m1" && found.status == "found")
        #expect(found.title == "Midnight City" && found.artist == "M83" && found.album == "Hurry Up, We're Dreaming")
        #expect(found.year == "2011")
        // The meter is clamped to 0…1 and the clock never runs backwards.
        #expect(found.level == 1 && found.elapsed == 0)
        // NEO sends null when it has no year: no "<null>" on the island.
        #expect(try #require(song(#"{"title":"t","year":null}"#)).year == nil)
        #expect(try #require(song(#"{"title":"t"}"#)).year == nil)
        #expect(try #require(song(#"{"title":"t","year":2011}"#)).year == nil)
        #expect(try #require(song(#"{"title":"t","year":"\#(String(repeating: "9", count: 40))"}"#)).year?.count == 12)
        #expect(try #require(song(#"{"title":"\#(String(repeating: "x", count: 400))"}"#)).title?.count == 120)

        // The cover: an image data URI, decoded; anything else, nothing.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let uri = "data:image/png;base64,\(png.base64EncodedString())"
        #expect(try #require(song(#"{"title":"t","cover":"\#(uri)"}"#)).cover == png)
        for bad in ["https://example.com/cover.png", "data:text/html;base64,\(png.base64EncodedString())",
                    "data:image/png;base64,not base64!", "data:image/png;base64"] {
            #expect(try #require(song(#"{"title":"t","cover":"\#(bad)"}"#)).cover == nil, "\(bad)")
        }
        // Past 1.5 MB of base64 it is dropped unread.
        let huge = "data:image/jpeg;base64," + String(repeating: "A", count: 1_500_004)
        #expect(try #require(song(#"{"title":"t","cover":"\#(huge)"}"#)).cover == nil)
        let justUnder = "data:image/jpeg;base64," + String(repeating: "A", count: 1_500_000)
        #expect(try #require(song(#"{"title":"t","cover":"\#(justUnder)"}"#)).cover?.count == 1_125_000)
        // No session, or no status: no state.
        #expect(NeoListener.facts(in: #"{"type":"song_state","data":{"status":"found"},"ts":1}"#).isEmpty)
        #expect(NeoListener.facts(in: #"{"type":"song_state","data":{"sid":"m1"},"ts":1}"#).isEmpty)
    }

    /// An NBF1 v1 packet as NEO's `pack_frame` lays it out: 64 header bytes
    /// (magic, version, kind, header length, the 16-byte session, …, the
    /// MIME code at byte 56), then the image.
    private func packet(sid: [UInt8] = Array(0..<16), version: UInt8 = 1, kind: UInt8 = 3, header: Int = 64,
                        mime: UInt8 = 1, image: Data = Data([0xFF, 0xD8, 0xFF, 0xD9])) -> Data {
        var bytes = [UInt8](repeating: 0, count: 64)
        bytes.replaceSubrange(0..<4, with: Array("NBF1".utf8))
        bytes[4] = version
        bytes[5] = kind
        bytes[6] = UInt8(header & 0xFF)
        bytes[7] = UInt8(header >> 8)
        bytes.replaceSubrange(8..<24, with: sid)
        bytes[56] = mime
        return Data(bytes) + image
    }

    @Test("a camera frame is read from NEO's NBF1 packet, and anything else is not a frame")
    func cameraFrames() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let parsed = NeoListener.cameraImage(in: packet(image: jpeg))
        // The session as NEO writes it in JSON: base64url, unpadded.
        #expect(parsed?.0 == Data(Array(0..<16) as [UInt8]).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""))
        #expect(parsed?.0.count == 22)
        #expect(parsed?.1 == jpeg)
        // A session id with the characters base64url swaps.
        #expect(NeoListener.cameraImage(in: packet(sid: [UInt8](repeating: 0xFB, count: 16)))?.0.contains { "+/=".contains($0) } == false)

        var wrongMagic = packet()
        wrongMagic[0] = UInt8(ascii: "X")
        let rejected: [(String, Data)] = [
            ("wrong magic", wrongMagic),
            ("another version", packet(version: 2)),
            ("a browser page, not the camera", packet(kind: 1)),
            ("a still", packet(kind: 2)),
            ("not a JPEG", packet(mime: 2)),
            ("a header shorter than the layout", packet(header: 32)),
            ("a header past the packet", packet(header: 200)),
            ("no image", packet(image: Data())),
            ("too short", Data(packet().prefix(63))),
            ("too big", packet(image: Data(count: 2_000_000))),
        ]
        for (name, data) in rejected {
            #expect(NeoListener.cameraImage(in: data) == nil, "\(name)")
        }
    }

    @Test("camera frames reach the island at most 24 times a second, however fast NEO sends them")
    func cameraFramePace() {
        let interval = NeoListener.cameraFrameInterval
        #expect(abs(interval - 1.0 / 24.0) < 1e-12)
        #expect(NeoListener.cameraFrameDue(at: 100 + interval, after: 100))
        #expect(!NeoListener.cameraFrameDue(at: 100 + interval * 0.9, after: 100))
        // The first frame always goes.
        #expect(NeoListener.cameraFrameDue(at: Date.timeIntervalSinceReferenceDate, after: 0))
        // NEO at 60 fps for one second: 20 frames go on, never more than 24.
        for fps in [30.0, 60.0, 120.0] {
            var last: TimeInterval = 0
            var shown = 0
            for i in 0..<Int(fps) {
                let now = 1000 + Double(i) / fps
                if NeoListener.cameraFrameDue(at: now, after: last) {
                    last = now
                    shown += 1
                }
            }
            #expect(shown <= 24 && shown >= Int(min(fps, 24)) / 2, "\(fps) fps → \(shown)")
        }
    }

    @Test("gentle check-ins: where the switch stands is read like the wake word, and goes out as the core's set command")
    func wellbeingCheckins() {
        #expect(NeoListener.coreSettings(in: #"{"type":"hello","data":{"state":"idle","wake_word":true,"wellbeing_checkins":false},"ts":1}"#)
            == NeoCoreSettings(wakeWord: true, wellbeingCheckins: false))
        // A settings event about check-ins alone is still where the switches stand.
        #expect(NeoListener.coreSettings(in: #"{"type":"settings","data":{"wellbeing_checkins":true},"ts":1}"#)
            == NeoCoreSettings(wellbeingCheckins: true))
        // Only a real boolean is an answer.
        for odd in [#""true""#, "1", "null"] {
            #expect(NeoListener.coreSettings(in: #"{"type":"settings","data":{"wellbeing_checkins":\#(odd)},"ts":1}"#) == nil, "\(odd)")
            #expect(NeoListener.coreSettings(in: #"{"type":"hello","data":{"state":"idle","wellbeing_checkins":\#(odd)},"ts":1}"#)
                == NeoCoreSettings(), "\(odd)")
        }
        #expect(NeoSetting.wellbeingCheckins(true).name == "wellbeing_checkins")
        #expect(NeoSetting.wellbeingCheckins(true).command == #"{"cmd":"set","name":"wellbeing_checkins","value":true}"#)
        #expect(NeoSetting.wellbeingCheckins(false).command == #"{"cmd":"set","name":"wellbeing_checkins","value":false}"#)
    }

    @Test("NEO's timers: the hello's list replaces them all; activity events start and end one; other kinds are not ours")
    func timers() {
        let pasta = NeoTimerInfo(id: "timer:3f2a9c1b7d4e", title: "Pasta", endsAt: Date(timeIntervalSince1970: 1_760_270_252))
        let unnamed = NeoTimerInfo(id: "timer:a1b2c3d4e5f6", title: "Timer", endsAt: Date(timeIntervalSince1970: 1_760_270_900.5))
        // The hello: after everything else it says, the timers counting down now.
        let hello = #"{"type":"hello","data":{"state":"idle","recent":[],"confirm":null,"timers":[{"id":"timer:3f2a9c1b7d4e","title":"Pasta","ends_at":1760270252.0},{"id":"timer:a1b2c3d4e5f6","title":"Timer","ends_at":1760270900.5}]}}"#
        #expect(NeoListener.facts(in: hello) == [.state(.idle), .neoTimers([pasta, unnamed])])
        // None running: said, so whatever the island knew is replaced by nothing.
        #expect(NeoListener.facts(in: #"{"type":"hello","data":{"state":"idle","timers":[]}}"#) == [.state(.idle), .neoTimers([])])
        // An older core says nothing about timers, and nothing new comes of its hello.
        #expect(NeoListener.facts(in: #"{"type":"hello","data":{"state":"idle","recent":[]}}"#) == [.state(.idle)])
        #expect(NeoListener.facts(in: #"{"type":"hello","data":{"state":"idle","timers":null}}"#) == [.state(.idle)])
        // A broken entry is skipped, the rest kept.
        let mixed = #"{"type":"hello","data":{"state":"idle","timers":[{"title":"no id","ends_at":1},{"id":"timer:3f2a9c1b7d4e","title":"Pasta","ends_at":1760270252},{"id":"timer:x","ends_at":"soon"},7]}}"#
        #expect(NeoListener.facts(in: mixed) == [.state(.idle), .neoTimers([pasta])])

        // Started (or restored after a restart), went off, cancelled.
        let present = #"{"type":"activity","data":{"op":"present","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","ends_at":1760270252.0,"done":false},"ts":1760270000.12}"#
        #expect(NeoListener.facts(in: present) == [.neoTimer(pasta)])
        let wentOff = #"{"type":"activity","data":{"op":"end","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","ends_at":1760270252.0,"done":true},"ts":1760270252.31}"#
        #expect(NeoListener.facts(in: wentOff) == [.neoTimerEnd(id: "timer:3f2a9c1b7d4e", title: "Pasta", done: true)])
        let cancelled = #"{"type":"activity","data":{"op":"end","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","ends_at":1760270252.0,"done":false},"ts":1760270100.02}"#
        #expect(NeoListener.facts(in: cancelled) == [.neoTimerEnd(id: "timer:3f2a9c1b7d4e", title: "Pasta", done: false)])
        // An end needs only its id: the island removes by id.
        #expect(NeoListener.facts(in: #"{"type":"activity","data":{"op":"end","id":"timer:3f2a9c1b7d4e","kind":"timer"}}"#)
            == [.neoTimerEnd(id: "timer:3f2a9c1b7d4e", title: "Timer", done: false)])
        // Only a real boolean says it went off.
        #expect(NeoListener.facts(in: #"{"type":"activity","data":{"op":"end","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","done":1}}"#)
            == [.neoTimerEnd(id: "timer:3f2a9c1b7d4e", title: "Pasta", done: false)])
        // Already past (restored late after the Mac slept): still a timer — the island shows 0:00.
        #expect(NeoListener.facts(in: #"{"type":"activity","data":{"op":"present","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","ends_at":1000.0,"done":false}}"#)
            == [.neoTimer(NeoTimerInfo(id: "timer:3f2a9c1b7d4e", title: "Pasta", endsAt: Date(timeIntervalSince1970: 1000)))])
        // The title is the user's (or a model's) words: one plain line, at most 40 characters.
        #expect(NeoListener.facts(in: #"{"type":"activity","data":{"op":"present","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta\nboil‮","ends_at":1760270252.0,"done":false}}"#)
            == [.neoTimer(NeoTimerInfo(id: "timer:3f2a9c1b7d4e", title: "Pasta boil", endsAt: pasta.endsAt))])

        // Later kinds may share the event: not ours. Nor is anything malformed.
        for other in [
            #"{"op":"present","id":"reminder:1","kind":"reminder","title":"Call","ends_at":1760270252.0,"done":false}"#,
            #"{"op":"present","id":"timer:3f2a9c1b7d4e","title":"Pasta","ends_at":1760270252.0,"done":false}"#,
            #"{"op":"update","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","ends_at":1760270252.0,"done":false}"#,
            #"{"op":"present","kind":"timer","title":"Pasta","ends_at":1760270252.0,"done":false}"#,
            #"{"op":"present","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","done":false}"#,
            #"{"op":"present","id":"timer:3f2a9c1b7d4e","kind":"timer","title":"Pasta","ends_at":true,"done":false}"#,
            #"{"op":"end","kind":"timer","title":"Pasta","done":true}"#,
            #"{"op":"end","id":42,"kind":"timer","done":true}"#,
        ] {
            #expect(NeoListener.facts(in: #"{"type":"activity","data":\#(other),"ts":1}"#).isEmpty, "\(other)")
        }
        #expect(NeoListener.facts(in: #"{"type":"activity","ts":1}"#).isEmpty)
    }

    @Test("NEO summoned by hand (the hotkey, the tray) is a fact for the panel")
    func woke() {
        #expect(NeoListener.facts(in: #"{"type":"woke","data":{"source":"ui"},"ts":1}"#) == [.woke])
        #expect(NeoListener.facts(in: #"{"type":"woke","data":{},"ts":1}"#) == [.woke])
    }

    @Test("garbage and unknown states yield nothing rather than a crash")
    func garbage() {
        #expect(NeoListener.facts(in: "not json").isEmpty)
        #expect(NeoListener.facts(in: "[1,2]").isEmpty)
        #expect(NeoListener.facts(in: #"{"type":"state","data":{"state":"dancing"}}"#).isEmpty)
        #expect(NeoListener.facts(in: #"{"type":"transcript","data":{"role":"robot","text":"x"}}"#).isEmpty)
    }

    @Test("the token is read from the one file, trimmed, and must look like one")
    func token() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("ws-token")
        #expect(NeoListener.readToken(at: file) == nil)
        let token = String(repeating: "ab", count: 32)
        try "\(token)\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(NeoListener.readToken(at: file) == token)
        try "short".write(to: file, atomically: true, encoding: .utf8)
        #expect(NeoListener.readToken(at: file) == nil)
        try "\(token)&x=y".write(to: file, atomically: true, encoding: .utf8)
        #expect(NeoListener.readToken(at: file) == nil)
        let url = NeoListener.socketURL(base: NeoListener.defaultURL, token: token)
        // The listener says what it is: a host — the one kind of client the
        // core takes NEO.app's menu actions from.
        #expect(url?.absoluteString == "ws://127.0.0.1:8765/?token=\(token)&role=host")
    }
}

/// Runs the listener against `Fixtures/neo_stub.py`, a stand-in for NEO's
/// core served by the `websockets` package in NEO's own virtualenv. Never the
/// real core: a scratch port and a scratch token file in a temp folder.
@Suite("NeoListener against a stub core", .serialized)
struct NeoListenerStubTests {

    /// A python with `websockets`: `NOTCHHUB_NEO_PYTHON` when it is set, else
    /// NEO's own virtualenv in a NEO checkout at `~/Documents/Neo 2.0/NEO`.
    /// Without one the stub tests are skipped.
    static let python = pythonURL(environment: ProcessInfo.processInfo.environment,
                                  home: FileManager.default.homeDirectoryForCurrentUser)
    static let pythonVariable = "NOTCHHUB_NEO_PYTHON"

    static func pythonURL(environment: [String: String], home: URL) -> URL {
        if let path = environment[pythonVariable], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return home.appendingPathComponent("Documents/Neo 2.0/NEO/.venv/bin/python")
    }

    @Test("the stub's python: NOTCHHUB_NEO_PYTHON when set, else the virtualenv under the user's own home folder")
    func pythonLocation() {
        let home = URL(fileURLWithPath: "/Users/alex", isDirectory: true)
        #expect(Self.pythonURL(environment: [:], home: home).path == "/Users/alex/Documents/Neo 2.0/NEO/.venv/bin/python")
        #expect(Self.pythonURL(environment: [Self.pythonVariable: ""], home: home).path == "/Users/alex/Documents/Neo 2.0/NEO/.venv/bin/python")
        #expect(Self.pythonURL(environment: [Self.pythonVariable: "/opt/neo/bin/python"], home: home).path == "/opt/neo/bin/python")
    }

    static let stub = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/neo_stub.py")

    /// Whether the stub can run here at all (the venv with `websockets`).
    static let available: Bool = {
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return false }
        let probe = Process()
        probe.executableURL = python
        probe.arguments = ["-c", "import websockets"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        do { try probe.run() } catch { return false }
        probe.waitUntilExit()
        return probe.terminationStatus == 0
    }()

    /// Collects facts from whatever thread the listener emits on.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var facts: [NeoFact] = []
        private var statuses: [NeoShellStatus] = []
        private var settings: [NeoCoreSettings] = []
        func record(_ event: SystemEvent) {
            lock.lock()
            defer { lock.unlock() }
            switch event.payload {
            case let .neo(fact): facts.append(fact)
            case let .neoShell(status): statuses.append(status)
            case let .neoSettings(core): settings.append(core)
            default: break
            }
        }
        /// What the core said about its own settings, in order.
        var cores: [NeoCoreSettings] {
            lock.lock()
            defer { lock.unlock() }
            return settings
        }
        var snapshot: [NeoFact] {
            lock.lock()
            defer { lock.unlock() }
            return facts
        }
        /// What NEO.app's shell reported, in order.
        var shells: [NeoShellStatus] {
            lock.lock()
            defer { lock.unlock() }
            return statuses
        }
    }

    /// The stub process and what it printed.
    private final class Stub: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var text = ""
        let port: Int
        let token = String(repeating: "7f", count: 32)
        let folder: URL
        var tokenFile: URL { folder.appendingPathComponent("ws-token") }

        init(drop: Bool, mode: String? = nil) throws {
            port = Int.random(in: 20_000...60_000)
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try token.write(to: tokenFile, atomically: true, encoding: .utf8)
            process.executableURL = NeoListenerStubTests.python
            process.arguments = [NeoListenerStubTests.stub.path, "\(port)", token] + (drop ? ["drop"] : []) + (mode.map { [$0] } ?? [])
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let self, let chunk = String(data: data, encoding: .utf8) else {
                    // EOF remains readable; unregister here or the dispatch
                    // source spins while Stub.stop waits for the child.
                    handle.readabilityHandler = nil
                    return
                }
                self.lock.lock()
                self.text += chunk
                self.lock.unlock()
            }
            try process.run()
        }

        var lines: [String] {
            lock.lock()
            defer { lock.unlock() }
            return text.split(separator: "\n").map(String.init)
        }

        func stop() {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return condition()
    }

    @Test("connects with the token, sends camera_view off and song_hello and nothing else, and relays the island's facts", .enabled(if: NeoListenerStubTests.available))
    func connectAndRelay() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }

        #expect(await waitFor { recorder.snapshot.contains(.state(.idle)) })
        let facts = recorder.snapshot
        #expect(facts == [
            .connected(true),
            .state(.listening), // from the hello — and nothing from its replay
            .transcript(role: .user, text: "hello neo", final: false),
            .state(.thinking),
            .card(.browser, open: true), // the card's own state in between is not ours
            .card(.browser, open: false),
            .transcript(role: .assistant, text: "Hi there", final: true),
            .note("quiet result"),
            .error("boom"),
            .state(.idle),
        ])

        // The stub refuses any Origin but NEO's own, so a connection proves
        // URLSession sent none. The host opts out of camera frames and asks
        // for an already-open song card after connecting.
        #expect(await waitFor { stub.lines.contains { $0.hasPrefix("CMD ") } })
        let commands = stub.lines.filter { $0.hasPrefix("CMD ") }
        #expect(commands == ["CMD " + NeoListener.cameraOffCommand, "CMD " + NeoListener.songHelloCommand])
        #expect(stub.lines.contains("ORIGIN -"))
        #expect(!stub.lines.contains { $0.hasPrefix("REJECT") })
        // …and with no Origin and `role=host`, the core counts it a host.
        #expect(stub.lines.contains("ROLE host"))

        // What NEO.app's shell reported: from the hello, then as it changed.
        let ready = NeoShellStatus(app: true, accessibility: true, screenRecording: true, openAtLogin: true, version: "2.1.0", hotkey: "⌥⌘")
        var missing = ready
        missing.screenRecording = false
        #expect(recorder.shells == [missing, ready])
        // …and where the core's own setting stands: from the hello.
        #expect(recorder.cores == [NeoCoreSettings(wakeWord: true)])
    }

    @Test("“Listen for Neo” goes out as the core's set command — only while the core is there — and the switch follows what the core then says", .enabled(if: NeoListenerStubTests.available))
    func wakeWordSwitch() async throws {
        let stub = try Stub(drop: false, mode: "settings")
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        // Flipped before the core is there: dropped, never kept for later.
        listener.send(NeoSetting.wakeWord(false))
        listener.start()
        #expect(await waitFor { recorder.cores == [NeoCoreSettings(wakeWord: true)] })
        #expect(stub.lines.contains("ROLE host")) // a host: one of the two that may switch it

        // The section's model says where the switch stands and what a tap asks
        // for; the monitor sends it, as the app's coordinator does.
        func model() -> NeoSettingsModel {
            NeoSettingsModel(featureOn: true, connected: true, shell: nil, core: recorder.cores.last)
        }
        #expect(model().listensForNeo && model().isEnabled(.wakeWord(false)))
        let monitor = SystemMonitor()
        monitor.register(listener)
        let off = try #require(NeoSettingsIntent.wakeWord(!model().listensForNeo).setting)
        monitor.neoSet(off)
        // The core applied it and told everyone: that is what moves the switch.
        #expect(await waitFor { recorder.cores.last == NeoCoreSettings(wakeWord: false) })
        #expect(!model().listensForNeo && model().wakeWordCaption.hasPrefix("Summon with ⌥⌘"))
        let on = try #require(NeoSettingsIntent.wakeWord(!model().listensForNeo).setting)
        monitor.neoSet(on)
        #expect(await waitFor { recorder.cores.last == NeoCoreSettings(wakeWord: true) })
        #expect(recorder.cores == [true, false, true].map { NeoCoreSettings(wakeWord: $0) })
        #expect(stub.lines.filter { $0.hasPrefix("CMD ") } == [
            "CMD " + NeoListener.cameraOffCommand,
            "CMD " + NeoListener.songHelloCommand,
            #"CMD {"cmd":"set","name":"wake_word","value":false}"#,
            #"CMD {"cmd":"set","name":"wake_word","value":true}"#,
        ])
        // The answers to its own requests (set_result) were no facts, and no settings.
        #expect(recorder.snapshot == [.connected(true), .state(.idle)])

        // Stopped: nothing more leaves.
        listener.stop()
        listener.send(NeoSetting.wakeWord(false))
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(stub.lines.filter { $0.contains(#""cmd":"set""#) }.count == 2)
    }

    @Test("NEO.app's menu actions go out as shell commands — only while the core is there", .enabled(if: NeoListenerStubTests.available))
    func shellActions() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        // Asked before the core is there: dropped, never kept for later.
        listener.send(.quit)
        listener.start()
        #expect(await waitFor { recorder.snapshot.contains(.connected(true)) })

        // Through the monitor, as the app's coordinator sends them.
        let monitor = SystemMonitor()
        monitor.register(listener)
        let actions: [NeoShellAction] = [.settings, .openLogs, .openAtLogin(false), .eraseMemory, .restart, .show]
        actions.forEach(monitor.neoShell)
        #expect(await waitFor { stub.lines.filter { $0.hasPrefix("CMD ") }.count == 2 + actions.count })
        #expect(stub.lines.filter { $0.hasPrefix("CMD ") } == [
            "CMD " + NeoListener.cameraOffCommand,
            "CMD " + NeoListener.songHelloCommand,
        ] + actions.map { "CMD " + $0.command })
        #expect(!stub.lines.contains { $0.contains(#""action":"quit""#) })

        // Stopped: nothing more leaves.
        listener.stop()
        listener.send(.quit)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!stub.lines.contains { $0.contains(#""action":"quit""#) })
    }

    @Test("Allow and Cancel go out as the page's own confirm command, over the host connection — and the core's confirm_done comes back", .enabled(if: NeoListenerStubTests.available))
    func confirmAnswers() async throws {
        let stub = try Stub(drop: false, mode: "confirm")
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let first = NeoConfirmCard(actionID: "trash:4d15b0099e5a9d0a", tool: "trash", summary: "move report.pdf to the Trash", detail: "/Users/me/Documents/report.pdf")
        let second = NeoConfirmCard(actionID: "shell:b7f034d65f0f4e1a", tool: "shell", summary: "run a command", detail: "mv '/Users/me/Documents/report.pdf' ~/.Trash/")
        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        // Answered before the core is there: dropped, never kept for later.
        listener.send(NeoConfirmAnswer(actionID: second.actionID, yes: true))
        listener.start()
        defer { listener.stop() }

        // The card pending at the hello, then the newer one that superseded it.
        #expect(await waitFor { recorder.snapshot.contains(.confirm(second)) })
        #expect(recorder.snapshot == [.connected(true), .state(.idle), .confirm(first), .confirmDone(first.actionID), .state(.confirming), .confirm(second)])
        #expect(stub.lines.contains("ROLE host")) // a host: one of the three that may answer

        // The model decides (Cancel always counts), the monitor sends, as the app does.
        var model = NeoConfirmModel()
        recorder.snapshot.forEach { model.receive($0, at: Date()) }
        #expect(model.card == second && model.isShowing)
        let monitor = SystemMonitor()
        monitor.register(listener)
        // A stale card's button closes nothing…
        monitor.neoConfirm(NeoConfirmAnswer(actionID: first.actionID, yes: true))
        // …the pending card's Cancel does.
        let cancel = model.answer(.cancel, at: Date())
        let answer = try #require(cancel)
        monitor.neoConfirm(answer)
        #expect(await waitFor { recorder.snapshot.contains(.confirmDone(second.actionID)) })
        let commands = stub.lines.filter { $0.hasPrefix("CMD ") }
        #expect(commands == [
            "CMD " + NeoListener.cameraOffCommand,
            "CMD " + NeoListener.songHelloCommand,
            #"CMD {"cmd":"confirm","yes":true,"action_id":"trash:4d15b0099e5a9d0a"}"#,
            #"CMD {"cmd":"confirm","yes":false,"action_id":"shell:b7f034d65f0f4e1a"}"#,
        ])
        #expect(recorder.snapshot.suffix(2) == [.confirmDone(second.actionID), .state(.idle)])
        #expect(recorder.snapshot.filter { $0 == .confirmDone(first.actionID) }.count == 1) // the stale answer closed nothing
    }

    @Test("NEO's timers arrive over the socket: the hello's, then started, went off and cancelled — and nothing is sent back for them", .enabled(if: NeoListenerStubTests.available))
    func timers() async throws {
        let stub = try Stub(drop: false, mode: "timers")
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }

        let pasta = NeoTimerInfo(id: "timer:3f2a9c1b7d4e", title: "Pasta", endsAt: Date(timeIntervalSince1970: 1_760_270_252))
        let unnamed = NeoTimerInfo(id: "timer:a1b2c3d4e5f6", title: "Timer", endsAt: Date(timeIntervalSince1970: 1_760_270_900.5))
        let eggs = NeoTimerInfo(id: "timer:0123456789ab", title: "Eggs", endsAt: Date(timeIntervalSince1970: 1_760_270_400))
        #expect(await waitFor { recorder.snapshot.contains(.state(.idle)) })
        #expect(recorder.snapshot == [
            .connected(true),
            .state(.thinking),
            .neoTimers([pasta, unnamed]),
            .neoTimer(eggs),
            .neoTimerEnd(id: pasta.id, title: "Pasta", done: true),
            .neoTimerEnd(id: eggs.id, title: "Eggs", done: false),
            // (a later kind of activity in between: not ours)
            .state(.idle),
        ])
        // The island drives them through its own model: what is left is the unnamed one.
        var model = NeoTimers()
        recorder.snapshot.forEach { model.receive($0) }
        #expect(model.running == [unnamed.id: unnamed])
        // Display only: no timer command ever leaves.
        #expect(stub.lines.filter { $0.hasPrefix("CMD ") } == ["CMD " + NeoListener.cameraOffCommand, "CMD " + NeoListener.songHelloCommand])
    }

    @Test("hosting NEO's UI it says so on connecting, and hands the UI back as it stops", .enabled(if: NeoListenerStubTests.available))
    func hostsUI() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2, hostsUI: true) { recorder.record($0) }
        listener.start()
        #expect(await waitFor { stub.lines.filter { $0.hasPrefix("CMD ") }.count == 3 })
        #expect(stub.lines.filter { $0.hasPrefix("CMD ") } == [
            "CMD " + NeoListener.cameraOffCommand,
            "CMD " + NeoListener.hostNotchCommand,
            "CMD " + NeoListener.songHelloCommand,
        ])

        let began = Date()
        listener.stop() // waits, briefly, for the hand-back to leave
        #expect(Date().timeIntervalSince(began) < 1)
        #expect(await waitFor { stub.lines.contains("CMD " + NeoListener.hostWindowCommand) })
        #expect(recorder.snapshot.last == .connected(false))
    }

    /// NEO's page, served by `NeoSchemeHandler` from a temp folder into a
    /// real `WKWebView` with the host script injected, opens a websocket to
    /// the stub: the Origin it sends is exactly `neo://app` (what NEO's core
    /// admits), the token it uses is the injected one, and its message to
    /// the host comes back through the `neo` handler.
    @Test("a page from neo://app reaches the core with that origin and the injected token", .enabled(if: NeoListenerStubTests.available))
    @MainActor
    func pageOrigin() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = """
        <!doctype html><html><body><script>
        const port = new URLSearchParams(location.search).get("port");
        const ws = new WebSocket("ws://127.0.0.1:" + port + "/?token=" + encodeURIComponent(window.__NEO_WS_TOKEN__));
        ws.onopen = () => { ws.send(JSON.stringify({cmd: "page", host: window.__NEO_HOST__, area: window.__NEO_HOST_AREA__}));
          window.webkit.messageHandlers.neo.postMessage({type: "size", w: 420, h: 520}); };
        </script></body></html>
        """
        try page.write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        final class Messages: NSObject, WKScriptMessageHandler, @unchecked Sendable {
            var bodies: [Any] = []
            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { bodies.append(message.body) }
        }
        let messages = Messages()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(NeoSchemeHandler(folder: folder), forURLScheme: NeoSchemeHandler.scheme)
        configuration.userContentController.addUserScript(WKUserScript(
            source: NeoHostScript.source(token: stub.token, maxPage: CGSize(width: 760, height: 640)), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(messages, name: "neo")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 520), configuration: configuration)
        web.load(URLRequest(url: URL(string: "neo://app/index.html?port=\(stub.port)")!))

        #expect(await waitFor { stub.lines.contains { $0.hasPrefix("CMD {\"cmd\":\"page\"") } })
        #expect(stub.lines.contains("ORIGIN \(NeoSchemeHandler.origin)"))
        #expect(!stub.lines.contains { $0.hasPrefix("REJECT") })
        // A page is a page: it never asks to be a host (and the core would refuse it).
        #expect(stub.lines.contains("ROLE -") && !stub.lines.contains("ROLE host"))
        let command = stub.lines.first { $0.hasPrefix("CMD {\"cmd\":\"page\"") } ?? ""
        #expect(command.contains(#""host":"notch""#) && command.contains(#""area":{"w":760,"h":640}"#))
        #expect(await waitFor { !messages.bodies.isEmpty })
        #expect(messages.bodies.first.flatMap(NeoHostMessage.parse) == .size(CGSize(width: 420, height: 520)))
        web.stopLoading()
    }

    @Test("a dropped core is reported, and the listener comes back on its own", .enabled(if: NeoListenerStubTests.available))
    func reconnect() async throws {
        let stub = try Stub(drop: true)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }

        // First connection: scripted, then closed by the server.
        #expect(await waitFor { recorder.snapshot.contains(.connected(false)) })
        // Second connection on its own, with a fresh hello.
        #expect(await waitFor { stub.lines.contains("OPEN 2") })
        #expect(await waitFor { recorder.snapshot.filter { $0 == .connected(true) }.count == 2 })
        #expect(await waitFor { recorder.snapshot.filter { $0 == .state(.listening) }.count == 2 })
        let connections = recorder.snapshot.filter {
            if case .connected = $0 { return true } else { return false }
        }
        #expect(connections == [.connected(true), .connected(false), .connected(true)])
    }

    @Test("with no token file nothing is reported, and it connects once one appears", .enabled(if: NeoListenerStubTests.available))
    func waitsForToken() async throws {
        let stub = try Stub(drop: false)
        defer { stub.stop() }
        #expect(await waitFor { stub.lines.contains("READY") })
        let token = stub.token
        try FileManager.default.removeItem(at: stub.tokenFile)

        let recorder = Recorder()
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:\(stub.port)/")!, tokenFile: stub.tokenFile, reconnectDelay: 0.2) { recorder.record($0) }
        listener.start()
        defer { listener.stop() }
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(recorder.snapshot.isEmpty)
        #expect(!stub.lines.contains { $0.hasPrefix("OPEN") })

        try token.write(to: stub.tokenFile, atomically: true, encoding: .utf8)
        #expect(await waitFor { recorder.snapshot.contains(.connected(true)) })
    }

    @Test("with no core at the port the listener stays quiet and never crashes", .enabled(if: NeoListenerStubTests.available))
    func noCore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-neo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("ws-token")
        try String(repeating: "0a", count: 32).write(to: file, atomically: true, encoding: .utf8)

        let recorder = Recorder()
        // A port nobody listens on.
        let listener = NeoListener(url: URL(string: "ws://127.0.0.1:1/")!, tokenFile: file, reconnectDelay: 0.1) { recorder.record($0) }
        listener.start()
        try await Task.sleep(nanoseconds: 700_000_000)
        listener.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(recorder.snapshot.isEmpty)
    }
}
