import AppKit
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--neo-snapshots DIR`: the real `IslandView` with the pet posing as NEO,
/// rendered offscreen with `ImageRenderer` in each of NEO's states and in
/// the island shapes it can be in, so each pose can be checked without a
/// core or a screen recording. While NEO listens, the island's rim lights
/// (`NeoWakeOutlineView`). The hardware cutout is masked in black over each
/// row. An optional filter keeps only
/// the rows whose name contains it (`--neo-snapshots DIR listening`; `NEO
/// timer`: NEO's countdown in the compact bar, from the real model and
/// surface at a fixed clock). The
/// last row is NEO's panel (its chat hangs down from the notch, with no pet)
/// with a stand-in for the page: a web view cannot be rendered offscreen.
///
/// `--neo-glow-zoom DIR`: the fox and its listening treatment, enlarged.
@MainActor
enum NeoSnapshots {

    struct Row {
        let name: String
        let state: IslandState
        let neo: NeoState?
        var activity: Activity? = nil
        var wings: WingStatus? = nil
        /// Which frame of the pose to draw (its loop's n-th cel).
        var frame: Int = 0
        /// Retained as a label for older pulse comparison rows.
        var listeningFor: TimeInterval = 3
        /// The idle dock, where it is not the pet's home on the right.
        var dock: PetDock? = nil
        var drawsHardwareNotch: Bool = true
    }

    /// One row's island, as the app would lay it out and draw it right now.
    struct Scene {
        let view: AnyView
        /// The island's frame on the screen, and in the rendered region.
        let frame: CGRect
        let local: CGRect
        let content: IslandContentSize
        let pet: PetLayout.Placement?
        let rowHeight: CGFloat
    }

    static let wingsSample = WingStatus(left: WingItem(symbol: "safari", label: "Safari"), right: [WingItem(symbol: "wifi", label: "Wi-Fi"), WingItem(symbol: "battery.100.bolt", label: "82%", tint: .accent)], musicPlaying: false, strip: nil)
    static let songSample = Activity.music(title: "Midnight City", artist: "M83")
    static let coverSample: Data? = {
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        NSGradient(colors: [.systemBlue, .systemPurple])?.draw(in: NSRect(origin: .zero, size: image.size), angle: 45)
        NSColor.systemPink.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: CGRect(x: 22, y: 22, width: 52, height: 52)).fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: CGRect(x: 41, y: 41, width: 14, height: 14)).fill()
        image.unlockFocus()
        return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
    }()

    /// The margin of desktop drawn on either side of the notch.
    static let margin: CGFloat = 360

    /// NEO's countdown as the island carries it: `timers` fed through the
    /// real model and surface at `now`, as the app drives them — and, with
    /// `goingOff`, one more that just went off.
    static func neoTimerActivity(_ timers: [NeoTimerInfo], goingOff: String? = nil, at now: Date) -> Activity? {
        var model = NeoTimers()
        var surface = NeoTimerSurface()
        let queue = ActivityQueue()
        let started = model.receive(.neoTimers(timers))
        surface.apply(started, timers: model, shows: true, in: queue, at: now)
        if let goingOff {
            let ended = model.receive(.neoTimerEnd(id: "timer:000000000000", title: goingOff, done: true))
            surface.apply(ended, timers: model, shows: true, in: queue, at: now)
        }
        return queue.current
    }

    /// The compact bar with NEO's timers: the soonest counting down (and a
    /// second later, as wide), a long name and a wide script cut before the
    /// clock, an unnamed one past an hour, one restored late, the "done"
    /// moment, and the countdown while NEO listens.
    static func neoTimerRows() -> [Row] {
        let clock = Date(timeIntervalSince1970: 1_760_270_000)
        func timer(_ id: String, _ title: String, _ seconds: TimeInterval) -> NeoTimerInfo {
            NeoTimerInfo(id: "timer:\(id)", title: title, endsAt: clock.addingTimeInterval(seconds))
        }
        let two = [timer("3f2a9c1b7d4e", "Pasta", 252), timer("a1b2c3d4e5f6", "Timer", 900.5)]
        let cases: [(String, NeoState, Activity?)] = [
            ("NEO idle — the soonest of two counts down", .idle, neoTimerActivity(two, at: clock)),
            ("one second later — the same width", .idle, neoTimerActivity(two, at: clock.addingTimeInterval(1))),
            ("a long name — cut, the clock whole", .idle, neoTimerActivity([timer("1", "Take the bread out of the oven", 90)], at: clock)),
            ("a wide script — cut at a music title's width", .idle, neoTimerActivity([timer("2", "パスタを茹でるタイマー長い名前です", 90)], at: clock)),
            ("unnamed, past an hour", .idle, neoTimerActivity([timer("3", "Timer", 3_852)], at: clock)),
            ("restored late — 0:00 until NEO says it went off", .idle, neoTimerActivity([timer("4", "Pasta", -40)], at: clock)),
            ("went off — the done moment", .idle, neoTimerActivity([timer("5", "Tea", 900)], goingOff: "Pasta", at: clock)),
            ("NEO listening — wake rim lit", .listening, neoTimerActivity(two, at: clock)),
        ]
        return cases.map { name, neo, activity in
            Row(name: "compact (NEO timer), \(name)", state: .compact, neo: neo, activity: activity)
        }
    }

    /// The island's content size and its frame on the screen for `row`, as
    /// the app would lay it out.
    static func layout(_ row: Row, geometry: NotchGeometry) -> (content: IslandContentSize, frame: CGRect) {
        var content: IslandContentSize
        switch row.state {
        case .expanded where row.activity?.kind == .identifiedSong:
            content = .default
            if let activity = row.activity {
                let textWidth = max(IslandMetrics.textWidth(activity.title), IslandMetrics.textWidth(activity.subtitle ?? ""))
                let popupWidth = min(max(320, 38 + DesignTokens.space12 + textWidth
                    + DesignTokens.contentInset * 2 + 8 + PetLayout.expandedReserve + 32), 420)
                content.expandedSize = CGSize(width: popupWidth, height: 80)
            }
        case .wings:
            let sides = IslandMetrics.wings(row.wings ?? WingStatus(), petSlot: PetLayout.barSlot)
            content = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: sides.trail)
            content.wingLead = sides.lead
        case .compact:
            content = row.activity.map { IslandMetrics.compact($0, petSlot: PetLayout.barSlot) } ?? .default
        default:
            content = .default
        }
        if row.state == .idle {
            content.petDock = row.dock ?? .home
        }
        return (content, geometry.frame(for: row.state, content: content))
    }

    /// `row`'s island as the app would draw it. By default the region is the
    /// notch with `margin` of desktop on either side, on a mid-grey desktop;
    /// `--neo-outline-frames` passes its own region (`regionMinX` in screen
    /// points, `regionSize`), no background (it composes its own backdrops),
    /// and the wake outline's clock, entrance/exit progress, whether it is
    /// listening (`false` for an exit's frames) and tint.
    static func scene(
        _ row: Row, geometry: NotchGeometry,
        regionMinX customMinX: CGFloat? = nil, regionSize: CGSize? = nil,
        outlineClock: Date? = nil, outlineActivation: Double? = nil, outlineActive: Bool? = nil, glow: UInt32? = nil,
        outlineReduceMotion: Bool? = nil,
        background: Color? = Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45)
    ) -> Scene {
        let notch = geometry.notchFrame
        let regionMinX = customMinX ?? notch.minX - margin
        let regionWidth = regionSize?.width ?? notch.width + margin * 2
        let notchHeight = notch.height
        // Use a fresh date per row for consistent pet animation frames.
        let now = Date()
        let (content, frame) = layout(row, geometry: geometry)
        let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
        // The pose as the brain gives it, started so that the wanted cel shows now.
        let petModel: PetRenderModel? = row.state == .neoPanel ? nil : {
            let id = row.neo.map(PetBrain.neoAnimation(for:)) ?? .sit
            let started = now.addingTimeInterval(-Double(row.frame) * id.animation.frameDuration - 0.001)
            return PetRenderModel(presentation: PetPresentation(
                mood: (row.neo ?? .idle) == .idle ? .idle : .neo, animation: id, startedAt: started,
                mirrored: row.state == .idle && row.dock?.side == .left
            ), glow: glow)
        }()
        let panelHeight = geometry.frame(for: .neoPanel, content: .default).height
        let rowHeight = regionSize?.height ?? (row.state == .neoPanel ? panelHeight + 8 : max(44, NotchGeometry.expandedHeight + 8))
        let placeholder: AnyView? = row.state == .neoPanel
            ? AnyView(VStack(spacing: 8) {
                Text("NEO's chat page (a WKWebView, served from neo://app/)").font(.system(size: 12, weight: .semibold))
                Text("transcript · confirm buttons · browser, camera and song cards").font(.system(size: 11))
            }.foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity))
            : nil
        let view = IslandView(
            current: row.activity, stackCount: 0, state: row.state, localFrame: local, cornerRadius: 10,
            notchInset: notchHeight, isIdle: row.state == .idle, wingStatus: row.wings ?? WingStatus(),
            notchWidth: notch.width, contentSize: content, panelContent: placeholder, surfaceVisible: true, pet: petModel, hasNotch: true,
            listening: nil,
            neoListeningActive: outlineActive ?? (row.neo == .listening),
            neoListeningClock: outlineClock,
            neoListeningActivation: outlineActivation,
            neoListeningReduceMotion: outlineReduceMotion,
            notchFrame: CGRect(x: notch.minX - regionMinX, y: 0, width: notch.width, height: notch.height)
        )
        .frame(width: regionWidth, height: rowHeight)
        .background(background ?? .clear)
        let pet = row.state == .neoPanel ? nil
            : PetLayout.placement(for: row.state, islandSize: frame.size, notchHeight: notchHeight, dock: content.petDock ?? .home)
        return Scene(view: AnyView(view), frame: frame, local: local, content: content, pet: pet, rowHeight: rowHeight)
    }

    static func render(directory: String, filter: String? = nil) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - margin
        let regionWidth = notch.width + margin * 2

        var rows: [Row] = [Row(name: "idle, NEO ready (the pet's own life)", state: .idle, neo: .idle)]
        for state in NeoState.allCases where state != .idle {
            let animation = PetBrain.neoAnimation(for: state).animation
            let frames = max(1, min(animation.frames.count, animation.loops ? 4 : 2))
            for frame in 0..<frames {
                rows.append(Row(name: "idle, \(state.rawValue) — \(PetBrain.neoAnimation(for: state).rawValue) cel \(frame)", state: .idle, neo: state, frame: frame))
            }
        }
        let wings = wingsSample
        let song = songSample
        let songListening = Activity(kind: .songRecognition, title: "Listening for a song", subtitle: "Listening · 0:04")
        let identifiedSong = Activity(kind: .identifiedSong, title: "Midnight City", subtitle: "M83 · Hurry Up, We're Dreaming · 2011", artwork: coverSample)
        rows += [
            // Listening lights the island's rim, whatever its shape.
            Row(name: "idle, listening — wake rim lit", state: .idle, neo: .listening),
            Row(name: "idle on the LEFT of the notch, listening — wake rim lit", state: .idle, neo: .listening, dock: PetDock(side: .left, reach: PetLayout.idleDock)),
            Row(name: "wings, listening — wake rim lit", state: .wings, neo: .listening, wings: wings),
            Row(name: "compact (volume), listening — wake rim lit", state: .compact, neo: .listening, activity: .volume(0.62)),
            Row(name: "compact (song recognition), listening", state: .compact, neo: .listening, activity: songListening),
            Row(name: "identified song popup", state: .expanded, neo: .speaking, activity: identifiedSong, drawsHardwareNotch: false),
            Row(name: "expanded (music), listening — wake rim lit", state: .expanded, neo: .listening, activity: song),
            Row(name: "compact (volume), speaking", state: .compact, neo: .speaking, activity: .volume(0.62)),
            Row(name: "expanded (music), thinking", state: .expanded, neo: .thinking, activity: song),
            Row(name: "NEO panel (the chat, \(Int(NeoPanelLayout.standard.width))×\(Int(NeoPanelLayout.standard.height)) under the notch), speaking — no pet", state: .neoPanel, neo: .speaking),
        ]
        rows += neoTimerRows()

        if let filter, !filter.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(filter) }
            guard !rows.isEmpty else {
                print("no rows match \"\(filter)\"")
                return 1
            }
        }

        let panelHeight = geometry.frame(for: .neoPanel, content: .default).height
        let height: CGFloat = max(44, NotchGeometry.expandedHeight + 8)
        let scale: CGFloat = 2
        let rowHeight = Int(height * scale) + 6
        func rowPixels(_ row: Row) -> Int { row.state == .neoPanel ? Int((panelHeight + 8) * scale) + 6 : rowHeight }
        let totalHeight = rows.reduce(0) { $0 + rowPixels($1) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(regionWidth * scale), height: totalHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Int(regionWidth * scale), height: totalHeight))
        var rowTop = 0 // from the top of the image, in pixels

        for (index, row) in rows.enumerated() {
            let scene = scene(row, geometry: geometry)
            let frame = scene.frame
            let view = scene.view
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage else {
                print("\(row.name): render failed")
                continue
            }
            rowTop += rowPixels(row)
            let y = CGFloat(totalHeight - rowTop)
            context.draw(image, in: CGRect(x: 0, y: y, width: CGFloat(image.width), height: CGFloat(image.height)))
            if row.drawsHardwareNotch {
                context.saveGState()
                context.translateBy(x: 0, y: y + CGFloat(image.height))
                context.scaleBy(x: scale, y: -scale)
                context.addPath(NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: DesignTokens.radiusNotchTopFlare)
                    .path(in: CGRect(x: notch.minX - regionMinX, y: 0, width: notch.width, height: notch.height)).cgPath)
                context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
                context.fillPath()
                context.restoreGState()
            }
            var line = String(format: "row %d: %@ — island %.0f×%.0f", index, row.name, frame.width, frame.height)
            if row.activity?.kind == .neoTimer, let text = row.activity?.compactText {
                line += " — “\(text)”"
            }
            if row.neo == .listening {
                let plain = self.scene(Row(name: "", state: row.state, neo: .idle, activity: row.activity, wings: row.wings, dock: row.dock), geometry: geometry).frame
                let delta = frame.width - plain.width
                line += String(format: " — %+.0f pt listening width", delta)
                if abs(delta) > 0.5 { line += " — UNEXPECTED LISTENING GEOMETRY" }
                line += " — rim lit"
            }
            print(line)
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let suffix = filter.map { "-" + $0.lowercased().filter { $0.isLetter || $0.isNumber } } ?? ""
        let file = url.appendingPathComponent("neo-snapshots\(suffix).png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(file.path)
        return 0
    }

    // MARK: - The glow, enlarged

    /// `--neo-glow-zoom DIR`: the fox with its listening glow, cut out of the
    /// real island and enlarged — NEO idle, the pulse at its peak, and the
    /// pulse fading — in the notch strip (the 16-pt fox on its idle dock) and
    /// in the expanded island (the 32-pt fox).
    static func renderGlowZoom(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let regionMinX = geometry.notchFrame.minX - margin
        let peak = NeoListeningLayout.pulseRise
        let fading: TimeInterval = 1.0
        let zoom: CGFloat = 12
        let crop = CGSize(width: 60, height: 44) // points, centred on the pet

        func cut(_ row: Row) -> CGImage? {
            let scene = scene(row, geometry: geometry)
            guard let pet = scene.pet else { return nil }
            let renderer = ImageRenderer(content: scene.view)
            renderer.scale = zoom
            guard let image = renderer.cgImage else { return nil }
            let centre = CGPoint(x: scene.frame.minX - regionMinX + pet.origin.x + pet.size / 2, y: pet.origin.y + pet.size / 2)
            let top = min(max(0, centre.y - crop.height / 2), scene.rowHeight - crop.height)
            let rect = CGRect(x: (centre.x - crop.width / 2) * zoom, y: top * zoom, width: crop.width * zoom, height: crop.height * zoom)
            return image.cropping(to: rect.integral)
        }

        struct Cell { let caption: String; let image: CGImage }
        var lines: [[Cell]] = []
        for (shape, state, activity) in [("notch strip — idle dock, 16-pt fox", IslandState.idle, Activity?.none), ("expanded island, 32-pt fox", .expanded, songSample)] {
            var cells: [Cell] = []
            let shots: [(String, NeoState, TimeInterval)] = [
                ("NEO idle — no glow", .idle, 0),
                (String(format: "listening, the pulse at its peak (t = %.2f s)", peak), .listening, peak),
                (String(format: "listening, the pulse fading (t = %.1f s)", fading), .listening, fading),
            ]
            for (caption, neo, time) in shots {
                guard let image = cut(Row(name: caption, state: state, neo: neo, activity: activity, listeningFor: time)) else {
                    print("\(shape), \(caption): render failed")
                    return 1
                }
                cells.append(Cell(caption: "\(shape)\n\(caption)", image: image))
            }
            lines.append(cells)
        }

        let cellSize = CGSize(width: crop.width * zoom / 2, height: crop.height * zoom / 2)
        let sheet = VStack(spacing: 12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, cells in
                HStack(spacing: 12) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(decorative: cell.image, scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: cellSize.width, height: cellSize.height)
                            Text(cell.caption)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.11))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("neo-glow-zoom.png")
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(String(format: "glow %.0f pt around the 16-pt fox, %.0f pt around the 32-pt one; one pulse of %.1f s: opacity 0 → %.2f at %.2f s → 0, scale %.2f → %.2f → %.2f; at %.1f s opacity %.2f",
                     NeoListeningLayout.glowDiameter(petSize: 16), NeoListeningLayout.glowDiameter(petSize: 32),
                     NeoListeningLayout.pulseDuration, NeoListeningLayout.peakOpacity, peak,
                     NeoListeningLayout.pulseScaleRange.lowerBound, NeoListeningLayout.pulseScaleRange.upperBound, NeoListeningLayout.pulseScaleRange.lowerBound,
                     fading, NeoListeningLayout.glowOpacity(pulse: NeoListeningLayout.pulse(at: fading))))
        print(file.path)
        return 0
    }
}
