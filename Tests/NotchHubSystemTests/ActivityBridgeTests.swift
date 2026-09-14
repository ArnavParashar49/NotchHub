import Foundation
import Testing
import NotchHubCore
@testable import NotchHubSystem

@Suite("ActivityBridge")
struct ActivityBridgeTests {

    private func instructions(_ payload: SystemEvent.Payload) -> [IslandInstruction] {
        ActivityBridge.instructions(for: SystemEvent(source: .system, payload: payload))
    }

    @Test("a volume change surfaces transiently, over whatever is playing")
    func volumeIsTransient() {
        guard case let .presentTransient(activity)? = instructions(.volume(level: 0.4)).first else {
            Issue.record("expected a transient")
            return
        }
        #expect(activity.kind == .volume)
        #expect(activity.autoDismiss > 0)
    }

    @Test("plugging in clears the low-battery warning")
    func chargingClearsLowBattery() {
        let result = instructions(.battery(percent: 8, charging: true, chargingChanged: true))
        #expect(result.first == .remove(.lowBattery))
        #expect(result.count == 2)
    }

    @Test("a falling battery percentage and network path changes are status, not news")
    func quietStatus() {
        #expect(instructions(.battery(percent: 64, charging: false, chargingChanged: false)) == [.remove(.lowBattery), .refresh])
        #expect(instructions(.network(name: "Wi-Fi")) == [.refresh])
    }

    @Test("a song carries the player it came from")
    func nowPlayingCarriesSource() {
        let result = instructions(.nowPlaying(title: "Solo", artist: "Frank Ocean", isPlaying: true, artwork: nil, source: "com.spotify.client"))
        guard case let .present(activity)? = result.first else {
            Issue.record("expected present")
            return
        }
        #expect(activity.sourceBundleID == "com.spotify.client")
    }

    @Test("timer ticks and download progress update in place")
    func liveReadoutsUpsert() {
        guard case .upsert? = instructions(.timerTick(elapsed: 3)).first,
              case let .upsert(download)? = instructions(.downloadProgress(name: "a.zip", progress: nil, bytes: 2_000)).first else {
            Issue.record("expected upserts")
            return
        }
        #expect(download.progress == nil)
        #expect(instructions(.timerFinished) == [.remove(.timer)])
    }

    @Test("a running coding agent is wing status; finishing is a brief transient")
    func codingAgentLifecycle() {
        #expect(instructions(.codingAgent(running: true, agent: "Claude Code")) == [.refresh])
        guard case let .presentTransient(activity)? = instructions(.codingAgent(running: false, agent: "Claude Code")).first else {
            Issue.record("expected a transient")
            return
        }
        #expect(activity.autoDismiss > 0)
    }

    @Test("status that is merely true right now never takes the island")
    func statusEventsRefreshOnly() {
        #expect(instructions(.weather(temperature: 21, condition: "Clear", symbol: "sun.max.fill")) == [.refresh])
        #expect(instructions(.privacy(camera: true, microphone: true)) == [.refresh])
        #expect(instructions(.frontmostApp(nil)) == [.refresh])
        #expect(instructions(.didWake).isEmpty)
    }

    @Test("stopping things removes their surfaces")
    func stopsRemove() {
        #expect(instructions(.nowPlayingStopped) == [.remove(.music)])
        #expect(instructions(.meetingEnded) == [.remove(.meeting)])
        #expect(instructions(.screenRecording(active: false)) == [.remove(.recording)])
        #expect(instructions(.focus(active: false, name: nil)) == [.remove(.focus)])
    }

    @Test("every transient announcement has a finite lifetime")
    func transientsExpire() {
        let payloads: [SystemEvent.Payload] = [
            .battery(percent: 50, charging: false, chargingChanged: true),
            .brightness(level: 0.5),
            .network(name: "Wi-Fi"),
            .bluetoothDevice(connected: true, name: "AirPods Pro"),
            .bluetoothDevice(connected: true, name: "Keyboard"),
            .focus(active: true, name: "Work"),
            .wifi(ssid: "Home", connected: true),
            .calendarStarting(title: "Standup", inMinutes: 5),
            .notification(app: "Mail", title: "Hi", body: "There"),
            .downloadFinished(name: "a.zip"),
        ]
        for payload in payloads {
            for instruction in instructions(payload) {
                switch instruction {
                case let .presentTransient(activity):
                    #expect(activity.autoDismiss > 0, "\(payload) must expire")
                case let .upsert(activity) where activity.subtitle == "Complete":
                    #expect(activity.autoDismiss > 0, "\(payload) must expire")
                case .present:
                    Issue.record("\(payload) must not hold the island persistently")
                default:
                    break
                }
            }
        }
    }
}
