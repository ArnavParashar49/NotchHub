import Foundation
import Testing
@testable import NotchHubOrbs

/// The port is checked against frames dumped from the JS engine itself
/// (`scripts/orb_goldens.mjs`): every state, several sizes and times, every
/// dot and line, in draw order, within 1e-3.
@Suite("Orb goldens")
struct OrbGoldenTests {

    struct Golden: Decodable {
        struct Frame: Decodable {
            let state: String
            let size: Int
            let t: Double
            let mode: String
            let speed: Double
            let opts: [String: Double]
            let dots: [[Double]]
            let lines: [[Double]]
        }
        let library: String
        let version: String
        let frames: [Frame]
    }

    static let tolerance = 1e-3

    static func load() throws -> Golden {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/thinking-orbs.json")
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    @Test("the goldens are from thinking-orbs 0.3.2 and cover every state")
    func provenance() throws {
        let golden = try Self.load()
        #expect(golden.library == "thinking-orbs")
        #expect(golden.version == "0.3.2")
        let states = Set(golden.frames.map(\.state))
        #expect(states == Set(OrbState.allCases.map(\.rawValue)))
    }

    @Test("every (state, size) resolves to the JS mode, speed and options")
    func presets() throws {
        for frame in try Self.load().frames {
            let state = try #require(OrbState(rawValue: frame.state))
            let size = try #require(OrbSizePreset(rawValue: frame.size))
            let resolved = OrbEngine.resolvePreset(state: state, size: size)
            #expect(resolved.mode.rawValue == frame.mode, "\(frame.state)@\(frame.size)")
            #expect(abs(resolved.speed - frame.speed) < 1e-9, "\(frame.state)@\(frame.size)")
            #expect(resolved.opts.keys.sorted() == frame.opts.keys.sorted(), "\(frame.state)@\(frame.size) option keys")
            for (key, value) in frame.opts {
                let ours = resolved.opts[key] ?? .nan
                #expect(abs(ours - value) < 1e-9, "\(frame.state)@\(frame.size) \(key): \(ours) vs \(value)")
            }
        }
    }

    /// Matches our dots to the golden's. Both lists are z-sorted, so each
    /// golden dot's match lies within a short window of the same index — but
    /// dots at the SAME depth (a face-on ring's lanes, mirror-image dots, a
    /// packet sitting on its node) fall in whatever order last-bit noise
    /// leaves them, which differs between the two runtimes, and the goldens
    /// carry five decimals. So a golden dot matches the nearest unmatched dot
    /// of ours within the window, every field within tolerance; the window
    /// is what keeps the far → near order checked.
    static func worstError(ours: [[Double]], golden: [[Double]], window: Int = 64) -> (error: Double, at: String) {
        var used = [Bool](repeating: false, count: ours.count)
        var worst = 0.0
        var worstAt = ""
        for (index, expected) in golden.enumerated() {
            var best: (error: Double, index: Int, field: Int)?
            for candidate in max(0, index - window)...min(ours.count - 1, index + window) where !used[candidate] {
                var error = 0.0
                var field = 0
                for (i, pair) in zip(ours[candidate], expected).enumerated() where abs(pair.0 - pair.1) > error {
                    error = abs(pair.0 - pair.1)
                    field = i
                }
                if best == nil || error < best!.error { best = (error, candidate, field) }
            }
            guard let best else { return (.infinity, "dot \(index): nothing left to match") }
            used[best.index] = true
            if best.error > worst {
                worst = best.error
                worstAt = "dot \(index) ~ ours \(best.index), field \(best.field): \(ours[best.index][best.field]) vs \(expected[best.field])"
            }
        }
        return (worst, worstAt)
    }

    @Test("every golden frame's geometry matches dot for dot, in draw order")
    func frames() throws {
        for frame in try Self.load().frames {
            let state = try #require(OrbState(rawValue: frame.state))
            let size = try #require(OrbSizePreset(rawValue: frame.size))
            let resolved = OrbEngine.resolvePreset(state: state, size: size)
            let ours = OrbEngine.frame(mode: resolved.mode, size: Double(frame.size), t: frame.t, opts: resolved.opts)
            let label = "\(frame.state)@\(frame.size) t=\(frame.t)"

            #expect(ours.dots.count == frame.dots.count, "\(label): \(ours.dots.count) dots vs \(frame.dots.count)")
            #expect(ours.lines.count == frame.lines.count, "\(label): \(ours.lines.count) lines vs \(frame.lines.count)")
            guard ours.dots.count == frame.dots.count, ours.lines.count == frame.lines.count else { continue }

            // Draw order: far to near, as the painter relies on.
            #expect(zip(ours.dots, ours.dots.dropFirst()).allSatisfy { $0.z <= $1.z }, "\(label): not z-sorted")

            let dots = Self.worstError(ours: ours.dots.map { [$0.x, $0.y, $0.z, $0.r, $0.white, $0.a] }, golden: frame.dots)
            #expect(dots.error < Self.tolerance, "\(label): worst dot error \(dots.error) at \(dots.at)")

            // Lines keep their emission order in both; compare them in place.
            var worst = 0.0
            var worstAt = ""
            for (index, expected) in frame.lines.enumerated() {
                let line = ours.lines[index]
                let values = [line.x1, line.y1, line.x2, line.y2, line.white, line.a, line.w]
                for (field, pair) in zip(["x1", "y1", "x2", "y2", "white", "a", "w"], zip(values, expected)) {
                    let error = abs(pair.0 - pair.1)
                    if error > worst {
                        worst = error
                        worstAt = "line \(index).\(field) \(pair.0) vs \(pair.1)"
                    }
                }
            }
            #expect(worst < Self.tolerance, "\(label): worst line error \(worst) at \(worstAt)")
        }
    }

    @Test("a frame is finished: visible, radius-clamped, far-to-near, stable")
    func finalize() {
        let dots = [
            OrbDot(x: 0, y: 0, z: 0.5, r: 0.1, white: 0.2),
            OrbDot(x: 1, y: 0, z: -0.5, r: 1, white: 0.2, a: 0.01),
            OrbDot(x: 2, y: 0, z: 0.5, r: 2, white: 0.2),
            OrbDot(x: 3, y: 0, z: -1, r: 3, white: 0.2),
        ]
        let frame = OrbEngine.finalizeFrame(dots, [OrbLine(x1: 0, y1: 0, x2: 1, y2: 1, white: 0.4, a: 0.001, w: 1)], rMin: 0.3)
        #expect(frame.dots.map(\.x) == [3, 0, 2])
        #expect(frame.dots[1].r == 0.3)
        #expect(frame.lines.isEmpty)
    }

    @Test("the lane's orb size picks the nearest tuned preset")
    func nearestPreset() {
        #expect(OrbSizePreset.nearest(to: 24) == .small)
        #expect(OrbSizePreset.nearest(to: 27) == .medium)
        #expect(OrbSizePreset.nearest(to: 30) == .medium)
        #expect(OrbSizePreset.nearest(to: 60) == .large)
        #expect(OrbSizePreset.nearest(to: 18) == .small)
    }

    @Test("the ink is the JS rgba: mirrored on dark, rounded to 8 bits")
    func ink() {
        // white 0.3 on dark → (1 - 0.3) * 255 = 178.5 → 179
        #expect(abs(OrbView.inkLevel(0.3, dark: true) - 179.0 / 255) < 1e-9)
        // …and on light, 0.3 * 255 = 76.5 → 77
        #expect(abs(OrbView.inkLevel(0.3, dark: false) - 77.0 / 255) < 1e-9)
        #expect(OrbView.inkLevel(2, dark: true) == 0)
        #expect(OrbView.inkLevel(-1, dark: true) == 1)
    }
}
