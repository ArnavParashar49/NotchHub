import AppKit
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--neo-outline-frames DIR [LABEL]`: NEO's wake outline (`NeoWakeOutlineView`)
/// on the real `IslandView`, rendered offscreen frame by frame at a fixed
/// clock, so its motion can be inspected and compared without a core, a mic
/// or a screen recording.
///
/// For each island shape — `idle` (the fox docked), `notch` (the fox hiding
/// in the notch, so the island is exactly the hardware notch), `wings`,
/// `compact` (the song bar) and `expanded` (music) — and each variant — `grey` (a mid-grey
/// menu bar), `white` (a bright white wallpaper) and `xray` (grey, with the
/// physical notch a translucent red instead of black, to show whatever is
/// drawn underneath it) — it writes, into DIR/LABEL (or DIR without a label):
///
/// - `SHAPE/VARIANT/loop/` — one full loop of the beams, `loopFrames` frames;
/// - `SHAPE/VARIANT/enter/`, `exit/` — the light appearing and leaving,
///   `fadeFrames` frames at 30 fps, through the live fade;
/// - `SHAPE/VARIANT/episode/` (grey and white) — a whole listen in real time
///   at 30 fps: enter, one loop, exit — for `scripts/outline_gif.py`;
/// - `SHAPE-VARIANT-sheet.png` — the loop, entrance and exit tiled, each
///   frame labelled with its t;
/// - `SHAPE-VARIANT-zoom.png` — the bottom-left corner and the top-left
///   flare end at three moments, device pixels enlarged 4× (nearest);
/// - `manifest.json`, and a `frames.json` in every frame folder.
///
/// Frames are 2× (device pixels on a Retina display), cropped to the island
/// with `margin` points around it (the screen's top edge above). The physical
/// notch is drawn over the island as the screen shows it. Only the outline
/// follows the injected clock: the pet's pose and the song bar's visualizer
/// run on the wall clock.
///
/// Options after LABEL: `--outline-shapes idle,wings` and
/// `--outline-variants grey,xray` render a subset; `--outline-tint RRGGBB`
/// tints the outline as a pet glow setting would (default: no glow set, the
/// "Teal" setting).
@MainActor
enum NeoOutlineFrames {

    struct Shape {
        let name: String
        let row: NeoSnapshots.Row
    }

    enum NotchStyle: String { case black, xray }

    struct Variant {
        let name: String
        let desktop: CGColor
        let menuBar: CGColor
        let notch: NotchStyle
        /// Whether to write the real-time episode for the GIF.
        let episode: Bool
    }

    /// One frame of a sequence: when it is (`t`, from the sequence's start),
    /// the outline's clock, how far the light has come in, and whether NEO is
    /// still listening (`false` through an exit, as the live view sees it).
    struct Frame {
        let t: TimeInterval
        let clock: TimeInterval
        let activation: Double
        var listening = true
    }

    static let scale: CGFloat = 2
    static let margin: CGFloat = 40
    static let loopFrames = 48
    static let fadeFrames = 18
    static let fps: Double = 30
    /// The outline's clock when listening starts (its loop phase, ×loop): the
    /// live view starts wherever the wall clock happens to be.
    static let enterClock: TimeInterval = 0
    /// The outline's clock when listening ends in the `exit` sequence.
    static let exitClock: TimeInterval = 1.2
    static let zoom: CGFloat = 4

    static var shapes: [Shape] {
        [
            Shape(name: "idle", row: .init(name: "idle, fox docked", state: .idle, neo: .listening)),
            // The fox hiding in the notch (`PetBrain`'s mischief): the idle
            // island is then exactly the hardware notch.
            Shape(name: "notch", row: .init(name: "idle, fox hiding in the notch (island = notch)", state: .idle, neo: .listening,
                                             dock: PetDock(side: .right, reach: 0))),
            Shape(name: "wings", row: .init(name: "wings", state: .wings, neo: .listening, wings: NeoSnapshots.wingsSample)),
            Shape(name: "compact", row: .init(name: "compact, song bar", state: .compact, neo: .listening, activity: NeoSnapshots.songSample)),
            Shape(name: "expanded", row: .init(name: "expanded, music", state: .expanded, neo: .listening, activity: NeoSnapshots.songSample)),
        ]
    }

    static let variants: [Variant] = [
        Variant(name: "grey",
                desktop: CGColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1),
                menuBar: CGColor(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1),
                notch: .black, episode: true),
        Variant(name: "white",
                desktop: CGColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1),
                menuBar: CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1),
                notch: .black, episode: true),
        Variant(name: "xray",
                desktop: CGColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1),
                menuBar: CGColor(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1),
                notch: .xray, episode: false),
    ]

    // MARK: - Sequences

    static var loop: [Frame] {
        let period = NeoWakeOutlineView.loopDuration
        return (0..<loopFrames).map { i in
            let t = period * Double(i) / Double(loopFrames)
            return Frame(t: t, clock: t, activation: 1)
        }
    }

    static var enter: [Frame] {
        (0..<fadeFrames).map { i in
            let t = Double(i) / fps
            return Frame(t: t, clock: enterClock + t, activation: NeoWakeOutlineView.liveActivation(seconds: t, appearing: true))
        }
    }

    /// Live, the outline's timeline pauses when listening ends, so anything
    /// still drawn holds still while it fades. The first frame is the last
    /// one lit; listening ends right after it.
    static var exit: [Frame] {
        (0..<fadeFrames).map { i in
            guard i > 0 else { return Frame(t: 0, clock: exitClock, activation: 1) }
            let t = Double(i - 1) / fps
            return Frame(t: Double(i) / fps, clock: exitClock,
                         activation: NeoWakeOutlineView.liveActivation(seconds: t, appearing: false), listening: false)
        }
    }

    /// A whole listen in real time: the entrance's frames, one full loop,
    /// then the exit's — continuous on one clock, at `fps`.
    static var episode: [Frame] {
        let fade = Double(fadeFrames) / fps
        let end = fade + NeoWakeOutlineView.loopDuration
        let count = Int(((end + fade) * fps).rounded())
        return (0..<count).map { k in
            let t = Double(k) / fps
            if t < end {
                return Frame(t: t, clock: enterClock + t, activation: NeoWakeOutlineView.liveActivation(seconds: t, appearing: true))
            }
            return Frame(t: t, clock: enterClock + end,
                         activation: NeoWakeOutlineView.liveActivation(seconds: t - end, appearing: false), listening: false)
        }
    }

    // MARK: - Entry point

    static func run(arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: "--neo-outline-frames") else { return 1 }
        var positional: [String] = []
        var options: [String: String] = [:]
        var i = index + 1
        while i < arguments.count {
            let argument = arguments[i]
            if argument.hasPrefix("--outline-"), i + 1 < arguments.count {
                options[argument] = arguments[i + 1]
                i += 2
            } else if argument.hasPrefix("--") {
                i += 1
            } else {
                positional.append(argument)
                i += 1
            }
        }
        let directory = positional.first ?? "."
        let label = positional.count > 1 ? positional[1] : nil
        let only = options["--outline-shapes"].map { Set($0.split(separator: ",").map(String.init)) }
        let onlyVariants = options["--outline-variants"].map { Set($0.split(separator: ",").map(String.init)) }
        let glow = options["--outline-tint"].flatMap { UInt32($0.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) }

        var root = URL(fileURLWithPath: directory, isDirectory: true)
        if let label { root.appendPathComponent(label, isDirectory: true) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let geometry = NotchGeometry.detectMain()
        let started = Date()
        var manifestShapes: [[String: Any]] = []
        var written = 0
        for shape in shapes where only?.contains(shape.name) ?? true {
            let layout = NeoSnapshots.layout(shape.row, geometry: geometry)
            let region = cropRegion(island: layout.frame, geometry: geometry)
            let island = CGRect(x: layout.frame.minX - region.minX, y: 0, width: layout.frame.width, height: layout.frame.height)
            let notch = CGRect(x: geometry.notchFrame.minX - region.minX, y: 0,
                               width: geometry.notchFrame.width, height: geometry.notchFrame.height)
            let contour = contourSites(shape: shape, island: island, geometry: geometry)
            var variantNames: [String] = []
            for variant in variants where onlyVariants?.contains(variant.name) ?? true {
                variantNames.append(variant.name)
                let base = root.appendingPathComponent(shape.name).appendingPathComponent(variant.name)
                var sequences: [(String, [Frame])] = [("loop", loop), ("enter", enter), ("exit", exit)]
                if variant.episode { sequences.append(("episode", episode)) }
                var tiles: [String: [(Frame, CGImage)]] = [:]
                for (name, frames) in sequences {
                    let folder = base.appendingPathComponent(name, isDirectory: true)
                    try? FileManager.default.removeItem(at: folder)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    var entries: [[String: Any]] = []
                    for (n, frame) in frames.enumerated() {
                        guard let image = render(shape: shape, geometry: geometry, region: region, frame: frame,
                                                 variant: variant, glow: glow) else {
                            print("\(shape.name)/\(variant.name)/\(name) frame \(n): render failed")
                            return 1
                        }
                        let file = String(format: "%03d.png", n)
                        writePNG(image, to: folder.appendingPathComponent(file))
                        written += 1
                        entries.append(["file": file, "t": frame.t, "clock": frame.clock, "activation": frame.activation,
                                        "listening": frame.listening])
                        if name != "episode" { tiles[name, default: []].append((frame, image)) }
                    }
                    writeJSON([
                        "shape": shape.name, "variant": variant.name, "sequence": name,
                        "fps": name == "loop" ? Double(loopFrames) / NeoWakeOutlineView.loopDuration : fps,
                        "scale": scale, "margin_pt": margin,
                        "island_px": rectArray(island, scale: scale), "notch_px": rectArray(notch, scale: scale),
                        "loops": name == "loop",
                        "frames": entries,
                    ], to: folder.appendingPathComponent("frames.json"))
                }
                let sheetFile = root.appendingPathComponent("\(shape.name)-\(variant.name)-sheet.png")
                if let sheet = contactSheet(title: "\(label ?? "outline") · \(shape.row.name) · \(variant.name)", tiles: tiles) {
                    writePNG(sheet, to: sheetFile)
                }
                let zoomFile = root.appendingPathComponent("\(shape.name)-\(variant.name)-zoom.png")
                if let zoomSheet = zoomSheet(shape: shape, geometry: geometry, region: region, island: island,
                                              sites: contour, variant: variant, glow: glow, label: label) {
                    writePNG(zoomSheet, to: zoomFile)
                }
                print("\(shape.name)/\(variant.name): \(sheetFile.lastPathComponent), \(zoomFile.lastPathComponent)")
            }
            manifestShapes.append([
                "name": shape.name, "description": shape.row.name, "variants": variantNames,
                "island_pt_screen": rectArray(layout.frame, scale: 1),
                "crop_pt_screen": rectArray(region, scale: 1),
                "island_px": rectArray(island, scale: scale), "notch_px": rectArray(notch, scale: scale),
                "contour_fraction_bottom_left_corner": contour.corner,
                "contour_length_pt": contour.length,
            ])
        }
        writeJSON([
            "label": label ?? "", "scale": scale, "margin_pt": margin,
            "loop_duration_s": NeoWakeOutlineView.loopDuration, "beam_length_fraction": NeoWakeOutlineView.beamLength,
            "fade_duration_s": NeoWakeOutlineView.fadeDuration,
            "enter_clock_s": enterClock, "exit_clock_s": exitClock,
            "tint": glow.map { String(format: "%06X", $0) } ?? "none (Teal setting: DesignTokens.accent)",
            "shapes": manifestShapes,
        ], to: root.appendingPathComponent("manifest.json"))
        print(String(format: "%d frames in %.1f s → %@", written, Date().timeIntervalSince(started), root.path))
        return 0
    }

    // MARK: - Rendering

    /// The island with `margin` around it (and its top flares), from the top of the screen.
    static func cropRegion(island: CGRect, geometry: NotchGeometry) -> CGRect {
        let flare = DesignTokens.radiusNotchTopFlare
        let minX = (island.minX - flare - margin).rounded(.down)
        let maxX = (island.maxX + flare + margin).rounded(.up)
        return CGRect(x: minX, y: 0, width: maxX - minX, height: (island.height + margin).rounded(.up))
    }

    /// One frame: the backdrop, the island over it, then the physical notch.
    static func render(shape: Shape, geometry: NotchGeometry, region: CGRect, frame: Frame,
                       variant: Variant, glow: UInt32?) -> CGImage? {
        let scene = NeoSnapshots.scene(
            shape.row, geometry: geometry, regionMinX: region.minX, regionSize: region.size,
            outlineClock: Date(timeIntervalSinceReferenceDate: frame.clock), outlineActivation: frame.activation,
            outlineActive: frame.listening, glow: glow, background: nil
        )
        let renderer = ImageRenderer(content: scene.view)
        renderer.scale = scale
        renderer.isOpaque = false
        guard let island = renderer.cgImage else { return nil }
        let width = Int(region.width * scale), height = Int(region.height * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let notchHeight = geometry.notchFrame.height
        context.setFillColor(variant.desktop)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(variant.menuBar)
        context.fill(CGRect(x: 0, y: CGFloat(height) - notchHeight * scale, width: CGFloat(width), height: notchHeight * scale))
        context.draw(island, in: CGRect(x: 0, y: CGFloat(height - island.height), width: CGFloat(island.width), height: CGFloat(island.height)))
        // The hardware notch, as `NeoSnapshots` draws it: a hole in the screen.
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        let notch = CGRect(x: geometry.notchFrame.minX - region.minX, y: 0,
                           width: geometry.notchFrame.width, height: notchHeight)
        context.addPath(NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: DesignTokens.radiusNotchTopFlare)
            .path(in: notch).cgPath)
        switch variant.notch {
        case .black: context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        case .xray: context.setFillColor(CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 0.42))
        }
        context.fillPath()
        context.restoreGState()
        return context.makeImage()
    }

    // MARK: - Where things are on the contour

    struct Sites {
        /// The contour fraction at the middle of the bottom-left corner.
        let corner: Double
        /// The contour's length in points.
        let length: Double
    }

    /// Finds the bottom-left corner's place on the outline's contour, so the
    /// zooms can catch a beam there.
    static func contourSites(shape: Shape, island: CGRect, geometry: NotchGeometry) -> Sites {
        let surface = surfaceShape(for: shape)
        let path = NeoWakeOutlineView.contour(surface, in: island)
        let radius = min(surface.bottomLeadingRadius, island.width / 2, island.height - min(surface.topLeadingRadius, island.height / 2))
        let target = CGPoint(x: island.minX + radius * (1 - 1 / 2.squareRoot()), y: island.maxY - radius * (1 - 1 / 2.squareRoot()))
        var best = (fraction: 0.0, distance: CGFloat.infinity)
        let steps = 1000
        var length: CGFloat = 0
        var previous = path.trimmedPath(from: 0, to: 0.0001).currentPoint ?? .zero
        for k in 1...steps {
            let f = Double(k) / Double(steps)
            guard let point = path.trimmedPath(from: 0, to: f).currentPoint else { continue }
            length += hypot(point.x - previous.x, point.y - previous.y)
            previous = point
            let d = hypot(point.x - target.x, point.y - target.y)
            if d < best.distance { best = (f, d) }
        }
        return Sites(corner: best.fraction, length: Double(length))
    }

    /// The island's silhouette for a shape, as `IslandView.surfaceShape` makes it.
    static func surfaceShape(for shape: Shape) -> NotchShape {
        let row = shape.row
        if row.state == .idle {
            return NotchShape.surface(islandRadius: DesignTokens.radiusIslandBottom, idleDock: row.dock ?? .home)
        }
        let base = row.state == .wings ? DesignTokens.radiusWingBottom : DesignTokens.radiusIslandBottom
        let notchHeight = NotchGeometry.detectMain().notchFrame.height
        let height = NeoSnapshots.layout(row, geometry: .detectMain()).frame.height
        let scale = min(2, max(1, height / notchHeight))
        return NotchShape.surface(islandRadius: base * scale, idleDock: nil)
    }

    // MARK: - Sheets

    /// The sequences tiled, each frame labelled with its t, at 1 pt per point.
    static func contactSheet(title: String, tiles: [String: [(Frame, CGImage)]]) -> CGImage? {
        guard let first = tiles["loop"]?.first?.1 else { return nil }
        let tileWidth = CGFloat(first.width) / scale
        let columns = max(3, Int(2400 / (tileWidth + 8)))
        func section(_ name: String, _ caption: String) -> some View {
            let frames = tiles[name] ?? []
            let rows = stride(from: 0, to: frames.count, by: columns).map { Array(frames[$0..<min($0 + columns, frames.count)]) }
            return VStack(alignment: .leading, spacing: 6) {
                Text(caption).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Image(decorative: item.1, scale: scale)
                                    .interpolation(.high)
                                Text(String(format: "t %.3f s · clock %.3f · act %.2f%@", item.0.t, item.0.clock, item.0.activation,
                                            item.0.listening ? "" : " · off"))
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
        }
        let loopCaption = String(format: "loop — one cycle of %.1f s, %d frames (%.3f s apart)",
                                 NeoWakeOutlineView.loopDuration, loopFrames, NeoWakeOutlineView.loopDuration / Double(loopFrames))
        let fadeCaption = String(format: "%d frames at %.0f fps; the live fade is .easeOut(%.2f s)", fadeFrames, fps, NeoWakeOutlineView.fadeDuration)
        let sheet = VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            section("loop", loopCaption)
            section("enter", "entrance — \(fadeCaption); the beams start at clock \(enterClock) s")
            section("exit", "exit — \(fadeCaption); listening ends after the first frame (\"off\"): the live view drops the blue at once and fades what is left")
        }
        .padding(16)
        .background(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.11))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        return renderer.cgImage
    }

    /// The bottom-left corner and the top-left flare end, at three moments
    /// each: no beam near, a beam centred there, and a beam's tail leaving.
    /// Device pixels (2×) are enlarged `zoom`× with no smoothing.
    static func zoomSheet(shape: Shape, geometry: NotchGeometry, region: CGRect, island: CGRect, sites: Sites,
                          variant: Variant, glow: UInt32?, label: String?) -> CGImage? {
        let length = Double(NeoWakeOutlineView.beamLength)
        let period = NeoWakeOutlineView.loopDuration
        func time(phase: Double) -> TimeInterval {
            var p = phase.truncatingRemainder(dividingBy: 1)
            if p < 0 { p += 1 }
            return p * period
        }
        let flare = DesignTokens.radiusNotchTopFlare
        // Crops in points within the region: the corner with 32 pt of bottom
        // edge and 22 pt of side; the flare end with the top 20 pt.
        let cornerCrop = CGRect(x: island.minX - 14, y: island.maxY - 26, width: 48, height: 32)
        let flareCrop = CGRect(x: island.minX - flare - 18, y: 0, width: 48, height: 20)
        let moments: [(String, CGRect, [(String, TimeInterval)])] = [
            ("bottom-left corner", cornerCrop, [
                ("no beam near", time(phase: sites.corner + 0.25 - length / 2)),
                ("beam centred on the corner", time(phase: sites.corner - length / 2)),
                ("beam's tail leaving the corner", time(phase: sites.corner - length * 0.1)),
            ]),
            ("top-left flare end (the wrap)", flareCrop, [
                ("no beam near", time(phase: 0.25 - length / 2)),
                ("beam straddling the wrap", time(phase: -length / 2)),
                ("beam just after the wrap", time(phase: -length * 0.1)),
            ]),
        ]
        struct Cell { let caption: String; let image: CGImage }
        var lines: [(String, [Cell])] = []
        for (site, crop, times) in moments {
            var cells: [Cell] = []
            for (caption, t) in times {
                guard let frame = render(shape: shape, geometry: geometry, region: region,
                                         frame: Frame(t: t, clock: t, activation: 1), variant: variant, glow: glow),
                      let cut = frame.cropping(to: CGRect(x: crop.minX * scale, y: crop.minY * scale,
                                                          width: crop.width * scale, height: crop.height * scale).integral),
                      let big = enlarge(cut, by: zoom) else { return nil }
                cells.append(Cell(caption: String(format: "%@ — t %.3f s", caption, t), image: big))
            }
            lines.append((site, cells))
        }
        let sheet = VStack(alignment: .leading, spacing: 14) {
            Text("\(label ?? "outline") · \(shape.row.name) · \(variant.name) — 2× device pixels enlarged \(Int(zoom))× (nearest)")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 6) {
                    Text(line.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(line.1.enumerated()), id: \.offset) { _, cell in
                            VStack(alignment: .leading, spacing: 4) {
                                Image(decorative: cell.image, scale: 1).interpolation(.none)
                                Text(cell.caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.11))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        return renderer.cgImage
    }

    static func enlarge(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = Int(CGFloat(image.width) * factor), height = Int(CGFloat(image.height) * factor)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Files

    static func rectArray(_ rect: CGRect, scale: CGFloat) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map { Double($0 * scale) }
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    static func writeJSON(_ object: Any, to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }
}
