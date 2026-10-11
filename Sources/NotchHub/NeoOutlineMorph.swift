import AppKit
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--neo-outline-morph DIR [LABEL]`: what the wake outline does LIVE while
/// the island springs between shapes, and while the light comes and goes —
/// things an offscreen `ImageRenderer` cannot show, since it never runs an
/// animation.
///
/// The real `IslandRootView` is hosted in a borderless window that is fully
/// transparent (alpha 0), ignores the mouse and never activates, so nothing
/// appears on screen; SwiftUI still animates it on the display's clock, and
/// the hosting view is sampled with `cacheDisplay` every 1/60 s. Each change
/// goes through the same spring the app would pick (`IslandMotion.between`).
/// Samples are composed on the grey menu-bar backdrop (or another variant's
/// with `--outline-backdrop dark|white|grey`; `--outline-haze shaped|mask`
/// draws the settled haze one way only) with the physical notch in
/// black (and a red x-ray of the notch in `xray/`), into DIR/LABEL/morph:
///
/// - `NAME/NNN.png` + `frames.json` (t = real seconds since the change) and
///   `NAME-sheet.png` for each change: idle ⇄ wings, idle → compact,
///   compact ⇄ expanded, and the light's live entrance and exit;
/// - `pacing.txt`: how often the outline actually redraws, sampled as fast
///   as the main thread allows with the island at rest.
///
/// Times are wall-clock, so two runs differ by a frame or so; the pet and
/// the light run live.
@MainActor
enum NeoOutlineMorph {

    struct Pose {
        let row: NeoSnapshots.Row
        var listening = true
    }

    struct Change {
        let name: String
        let from: Pose
        let to: Pose
        var duration: TimeInterval = 0.9
    }

    static let scale: CGFloat = 2
    static let margin: CGFloat = 40

    static var changes: [Change] {
        let idle = NeoSnapshots.Row(name: "idle", state: .idle, neo: .listening)
        let wings = NeoSnapshots.Row(name: "wings", state: .wings, neo: .listening, wings: NeoSnapshots.wingsSample)
        let compact = NeoSnapshots.Row(name: "compact", state: .compact, neo: .listening, activity: NeoSnapshots.songSample)
        let expanded = NeoSnapshots.Row(name: "expanded", state: .expanded, neo: .listening, activity: NeoSnapshots.songSample)
        return [
            Change(name: "idle-to-wings", from: Pose(row: idle), to: Pose(row: wings)),
            Change(name: "wings-to-idle", from: Pose(row: wings), to: Pose(row: idle)),
            Change(name: "idle-to-compact", from: Pose(row: idle), to: Pose(row: compact)),
            Change(name: "compact-to-expanded", from: Pose(row: compact), to: Pose(row: expanded)),
            Change(name: "expanded-to-compact", from: Pose(row: expanded), to: Pose(row: compact)),
            Change(name: "live-enter-wings", from: Pose(row: wings, listening: false), to: Pose(row: wings), duration: 0.5),
            Change(name: "live-exit-wings", from: Pose(row: wings), to: Pose(row: wings, listening: false), duration: 0.5),
        ]
    }

    @MainActor
    final class Run {
        let root: URL
        let geometry: NotchGeometry
        let region: CGRect
        let model = IslandModel()
        let window: NSWindow
        let host: NSHostingView<IslandRootView>
        var queue: [Change]
        /// The wallpaper and menu bar the samples are composed on.
        var backdrop = NeoOutlineFrames.variants[0]
        // The change being sampled.
        var samples: [(TimeInterval, CGImage)] = []
        var start = Date()
        // The redraw-rate probe.
        var stamps: [TimeInterval] = []
        var last: Data?
        var count = 0
        /// The light's own frame count when the probe began, and its rate.
        var drawnAtStart = 0
        var drawnRate = 0.0
        /// CPU seconds per second, the island at rest without and with the light.
        var idleCPU = 0.0
        var litCPU = 0.0
        /// Instructions retired per second, the island at rest without and
        /// with the light: unlike CPU time, the same on a performance or an
        /// efficiency core and at any clock speed.
        var idleInstructions = 0.0
        var litInstructions = 0.0
        /// The memory footprint at rest, without and with the light, in MB.
        var idleFootprint = 0.0
        var litFootprint = 0.0
        /// How long the lit measurement runs.
        var quietSeconds: TimeInterval = 1
        init(root: URL, geometry: NotchGeometry, region: CGRect, queue: [Change]) {
            self.root = root
            self.geometry = geometry
            self.region = region
            self.queue = queue
            host = NSHostingView(rootView: IslandRootView(model: model))
            let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
            window = NSWindow(contentRect: CGRect(x: screen.minX, y: screen.minY, width: region.width, height: region.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        }
    }

    static func run(arguments: [String]) -> Never {
        let index = arguments.firstIndex(of: "--neo-outline-morph") ?? 0
        let positional = arguments.dropFirst(index + 1).prefix { !$0.hasPrefix("--") }
        var root = URL(fileURLWithPath: positional.first ?? ".", isDirectory: true)
        if positional.count > 1 { root.appendPathComponent(Array(positional)[1], isDirectory: true) }
        root.appendPathComponent("morph", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let geometry = NotchGeometry.detectMain()
        let frames = changes.flatMap { [$0.from.row, $0.to.row] }.map { NeoSnapshots.layout($0, geometry: geometry).frame }
        let flare = DesignTokens.radiusNotchTopFlare
        let minX = (frames.map(\.minX).min()! - flare - margin).rounded(.down)
        let maxX = (frames.map(\.maxX).max()! + flare + margin).rounded(.up)
        let region = CGRect(x: minX, y: 0, width: maxX - minX, height: (frames.map(\.height).max()! + margin).rounded(.up))

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // `--outline-pacing-only`: skip the changes and measure the redraw
        // rate and CPU alone (for profiling, with a longer lit stretch).
        let pacingOnly = arguments.contains("--outline-pacing-only")
        let run = Run(root: root, geometry: geometry, region: region, queue: pacingOnly ? [] : changes)
        run.quietSeconds = pacingOnly ? 4 : 1
        // `--outline-quiet SECONDS`: how long the lit measurement runs (two
        // runs of different lengths, differenced, give the settled light's
        // own cost with everything else cancelled out).
        if let index = arguments.firstIndex(of: "--outline-quiet"), index + 1 < arguments.count,
           let seconds = Double(arguments[index + 1]) {
            run.quietSeconds = seconds
        }
        // `--outline-haze shaped|mask`: the settled haze drawn one way only
        // (as `--neo-outline-frames` does), to compare the two live.
        if let index = arguments.firstIndex(of: "--outline-haze"), index + 1 < arguments.count {
            NeoWakeHaze.forced = NeoWakeHaze.Way(rawValue: arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "--outline-backdrop"), index + 1 < arguments.count,
           let variant = NeoOutlineFrames.variants.first(where: { $0.name == arguments[index + 1] }) {
            run.backdrop = variant
        }
        run.window.isOpaque = false
        run.window.backgroundColor = .clear
        run.window.hasShadow = false
        run.window.alphaValue = 0
        run.window.ignoresMouseEvents = true
        run.window.collectionBehavior = [.transient, .ignoresCycle]
        // Above ordinary windows, so nothing on screen can occlude it: AppKit
        // stops drawing an occluded window, and the probe would read as free.
        run.window.level = .statusBar
        run.host.frame = CGRect(origin: .zero, size: region.size)
        run.window.contentView = run.host
        run.window.orderFrontRegardless()
        print("morph: sampling in an invisible window, region \(Int(region.width))×\(Int(region.height)) pt")

        later(0.3) { next(run) }
        app.run()
        exit(0)
    }

    /// Runs `action` on the main actor after `seconds`.
    static func later(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { action() } }
    }

    /// Puts the model in `pose` (inside `withAnimation(animation)` when given).
    static func apply(_ pose: Pose, run: Run, animation: Animation?) {
        let layout = NeoSnapshots.layout(pose.row, geometry: run.geometry)
        let local = CGRect(x: layout.frame.minX - run.region.minX, y: 0, width: layout.frame.width, height: layout.frame.height)
        let model = run.model
        let update = {
            model.current = pose.row.activity
            model.state = pose.row.state
            model.contentSize = layout.content
            model.localFrame = local
            model.isIdle = pose.row.state == .idle
            model.wingStatus = pose.row.wings ?? WingStatus()
            model.notchInset = run.geometry.notchFrame.height
            model.notchWidth = run.geometry.notchFrame.width
            model.notchFrame = CGRect(x: run.geometry.notchFrame.minX - run.region.minX, y: 0,
                                      width: run.geometry.notchFrame.width, height: run.geometry.notchFrame.height)
            model.surfaceVisible = true
            model.hasNotch = true
            model.neoListeningActive = pose.listening
            if model.pet == nil {
                let id = PetBrain.neoAnimation(for: .listening)
                model.pet = PetRenderModel(presentation: PetPresentation(mood: .neo, animation: id, startedAt: Date()))
            }
        }
        if let animation { withAnimation(animation) { update() } } else { update() }
    }

    static func next(_ run: Run) {
        guard !run.queue.isEmpty else {
            pacing(run)
            return
        }
        let change = run.queue.removeFirst()
        apply(change.from, run: run, animation: nil)
        // Let the starting pose settle (and the light come fully in or out).
        later(0.6) {
            let fromFrame = run.model.localFrame
            let fromIdle = run.model.isIdle
            let toFrame = NeoSnapshots.layout(change.to.row, geometry: run.geometry).frame
            let toLocal = CGRect(x: toFrame.minX - run.region.minX, y: 0, width: toFrame.width, height: toFrame.height)
            let motion = IslandMotion.between(from: fromFrame, fromIdle: fromIdle, to: toLocal, toIdle: change.to.row.state == .idle)
            let animation = DesignTokens.animation(for: motion)
            run.samples = []
            if let still = snapshot(run) { run.samples.append((-0.0001, still)) }
            run.start = Date()
            apply(change.to, run: run, animation: animation)
            tick(run, change: change, motion: motion)
        }
    }

    static func tick(_ run: Run, change: Change, motion: IslandMotion) {
        let t = Date().timeIntervalSince(run.start)
        if let image = snapshot(run) { run.samples.append((t, image)) }
        if t < change.duration {
            later(1.0 / 60) { tick(run, change: change, motion: motion) }
        } else {
            save(change: change, motion: motion, samples: run.samples, run: run)
            next(run)
        }
    }

    static func snapshot(_ run: Run) -> CGImage? {
        guard let rep = run.host.bitmapImageRepForCachingDisplay(in: run.host.bounds) else { return nil }
        run.host.cacheDisplay(in: run.host.bounds, to: rep)
        return rep.cgImage
    }

    static func compose(_ island: CGImage, run: Run, notch style: NeoOutlineFrames.NotchStyle) -> CGImage? {
        let width = Int(run.region.width * scale), height = Int(run.region.height * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let backdrop = run.backdrop
        let notchHeight = run.geometry.notchFrame.height
        context.setFillColor(backdrop.desktop)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(backdrop.menuBar)
        context.fill(CGRect(x: 0, y: CGFloat(height) - notchHeight * scale, width: CGFloat(width), height: notchHeight * scale))
        context.draw(island, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        let notch = CGRect(x: run.geometry.notchFrame.minX - run.region.minX, y: 0, width: run.geometry.notchFrame.width, height: notchHeight)
        context.addPath(NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: DesignTokens.radiusNotchTopFlare)
            .path(in: notch).cgPath)
        context.setFillColor(style == .black ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                                             : CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 0.42))
        context.fillPath()
        context.restoreGState()
        return context.makeImage()
    }

    static func save(change: Change, motion: IslandMotion, samples: [(TimeInterval, CGImage)], run: Run) {
        for style in [NeoOutlineFrames.NotchStyle.black, .xray] {
            let folder = run.root.appendingPathComponent(style == .black ? change.name : "xray/\(change.name)", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var entries: [[String: Any]] = []
            var tiles: [(TimeInterval, CGImage)] = []
            for (n, sample) in samples.enumerated() {
                guard let image = compose(sample.1, run: run, notch: style) else { continue }
                let file = String(format: "%03d.png", n)
                NeoOutlineFrames.writePNG(image, to: folder.appendingPathComponent(file))
                entries.append(["file": file, "t": max(0, sample.0)])
                tiles.append((sample.0, image))
            }
            NeoOutlineFrames.writeJSON([
                "change": change.name, "motion": motion.rawValue, "scale": scale, "fps": 60, "loops": false,
                "realtime": true, "frames": entries,
            ], to: folder.appendingPathComponent("frames.json"))
            if style == .black, let sheet = sheet(title: "\(change.name) — \(motion.rawValue) spring, live samples", tiles: tiles) {
                NeoOutlineFrames.writePNG(sheet, to: run.root.appendingPathComponent("\(change.name)-sheet.png"))
            }
        }
        print("morph: \(change.name) (\(motion.rawValue)) — \(samples.count) samples")
    }

    static func sheet(title: String, tiles: [(TimeInterval, CGImage)]) -> CGImage? {
        guard let first = tiles.first?.1 else { return nil }
        let columns = max(2, Int(2400 / (CGFloat(first.width) / scale + 8)))
        let rows = stride(from: 0, to: tiles.count, by: columns).map { Array(tiles[$0..<min($0 + columns, tiles.count)]) }
        let view = VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Image(decorative: tile.1, scale: scale).interpolation(.high)
                            Text(tile.0 < 0 ? "before" : String(format: "t %.3f s", tile.0))
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.11))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    /// With the island at rest in its wings and listening, samples the view
    /// back to back for a second and counts how often what is drawn changes:
    /// the outline's real redraw rate (the pet holds a cel far longer).
    static func pacing(_ run: Run) {
        let wings = NeoSnapshots.Row(name: "wings", state: .wings, neo: .listening, wings: NeoSnapshots.wingsSample)
        apply(Pose(row: wings, listening: false), run: run, animation: nil)
        // The process's CPU time over a quiet second (no snapshots competing
        // for the main thread): first without the light, then with it, and
        // the light's own frame count meanwhile.
        later(0.6) {
            let idleStart = (Date(), cpuTime())
            let idleCount = instructions()
            later(1.0) {
                run.idleCPU = (cpuTime() - idleStart.1) / Date().timeIntervalSince(idleStart.0)
                run.idleInstructions = Double(instructions() - idleCount) / Date().timeIntervalSince(idleStart.0)
                run.idleFootprint = footprint()
                apply(Pose(row: wings), run: run, animation: nil)
                later(2.0) { // past the wake, into the settled light
                    let quietStart = (Date(), cpuTime())
                    let quietCount = instructions()
                    run.drawnAtStart = NeoWakeOutlineView.framesDrawn
                    later(run.quietSeconds) {
                        let seconds = Date().timeIntervalSince(quietStart.0)
                        run.drawnRate = Double(NeoWakeOutlineView.framesDrawn - run.drawnAtStart) / seconds
                        run.litCPU = (cpuTime() - quietStart.1) / seconds
                        run.litInstructions = Double(instructions() - quietCount) / seconds
                        run.litFootprint = footprint()
                        // …then what snapshots can see.
                        run.start = Date()
                        sample(run)
                    }
                }
            }
        }
    }

    /// This process's physical memory footprint, in MB.
    static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Instructions this process has retired so far.
    static func instructions() -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_instructions : 0
    }

    /// This process's user + system CPU time so far, in seconds.
    static func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    static func sample(_ run: Run) {
        let t = Date().timeIntervalSince(run.start)
        run.count += 1
        if let image = snapshot(run), let data = image.dataProvider?.data as Data? {
            if data != run.last { run.stamps.append(t); run.last = data }
        }
        guard t >= 1.0 else {
            later(0.002) { sample(run) }
            return
        }
        // Then listening ends; once the light has gone, the memory again.
        let sampled = (count: run.count, seconds: t, stamps: run.stamps)
        apply(Pose(row: NeoSnapshots.Row(name: "wings", state: .wings, neo: .listening, wings: NeoSnapshots.wingsSample), listening: false),
              run: run, animation: nil)
        later(2.0) { report(run, sampled: sampled, afterFootprint: footprint()) }
    }

    static func report(_ run: Run, sampled: (count: Int, seconds: TimeInterval, stamps: [TimeInterval]), afterFootprint: Double) {
        let stamps = sampled.stamps, t = sampled.seconds
        let gaps = zip(stamps.dropFirst(), stamps).map { $0 - $1 }.sorted()
        let median = gaps.isEmpty ? 0 : gaps[gaps.count / 2]
        let screenHz = NSScreen.main?.maximumFramesPerSecond ?? 0
        let report = String(format: """
            wake light redraw rate, island at rest (wings), listening, settled
            display: up to %d Hz (NSScreen.maximumFramesPerSecond)
            frames of light computed by its TimelineView over a quiet second: %.0f per second
              (the wake and the exit run at the display's rate; settled, the light asks for 60 — see NeoWakeOutlineView.settledInterval)
            process CPU at rest: %.1f %% without the light, %.1f %% with it → about %.2f ms of CPU per frame of light
            instructions retired: %.1f M/s without the light, %.1f M/s with it → %.2f M per frame of light
            memory footprint: %.1f MB without the light, %.1f MB with it, %.1f MB 2 s after it went out
            snapshots taken: %d in %.2f s (each cacheDisplay is slow, so this caps what they can see)
            distinct snapshots: %d → %.0f per second (median gap %.1f ms)

            """, screenHz, run.drawnRate, run.idleCPU * 100, run.litCPU * 100,
            run.drawnRate > 0 ? (run.litCPU - run.idleCPU) * 1000 / run.drawnRate : 0,
            run.idleInstructions / 1e6, run.litInstructions / 1e6,
            run.drawnRate > 0 ? (run.litInstructions - run.idleInstructions) / 1e6 / run.drawnRate : 0,
            run.idleFootprint, run.litFootprint, afterFootprint, sampled.count, t, stamps.count, Double(max(0, stamps.count - 1)) / t, median * 1000)
        print(report, terminator: "")
        try? report.write(to: run.root.appendingPathComponent("pacing.txt"), atomically: true, encoding: .utf8)
        exit(0)
    }
}
