import AppKit
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--neo-snapshots DIR`: the real `IslandView` with the pet posing as NEO,
/// rendered offscreen with `ImageRenderer` in each of NEO's states and in
/// the island shapes it can be in, so each pose can be checked without a
/// core or a screen recording. Every row's island is exactly the pre-NEO
/// island — the pet's pose is all that changes — except while NEO LISTENS:
/// then a soft glow breathes behind the pet, and for the first 1.5 s the word
/// "Listening" stands beside it and the pet's side makes room for the word
/// (t = 0.5 s: the word, the glow near its brightest; t = 3 s: the glow
/// alone, near its dimmest, and the island at its ordinary width). The
/// hardware notch is drawn over each row in translucent red: nothing of the
/// word may sit under it. An optional filter keeps only the rows whose name
/// contains it (`--neo-snapshots DIR listening`). The last row is NEO's panel
/// (its chat hangs down from the notch, with no pet) with a stand-in for the
/// page: a web view cannot be rendered offscreen.
///
/// `--neo-glow-zoom DIR`: the fox and its listening glow, enlarged, at the
/// top and the bottom of a breath — in the notch strip and in the expanded
/// island — so the light itself can be judged.
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
        /// How long NEO has been listening (rows where it is): under
        /// 1.5 s the word still stands beside the pet.
        var listeningFor: TimeInterval = 3
        /// The idle dock, where it is not the pet's home on the right.
        var dock: PetDock? = nil
    }

    /// One row's island, as the app would lay it out and draw it right now.
    struct Scene {
        let view: AnyView
        /// The island's frame on the screen, and in the rendered region.
        let frame: CGRect
        let local: CGRect
        let content: IslandContentSize
        let mark: NeoListeningMark?
        let pet: PetLayout.Placement?
        let rowHeight: CGFloat
    }

    static let wingsSample = WingStatus(left: WingItem(symbol: "safari", label: "Safari"), right: [WingItem(symbol: "wifi", label: "Wi-Fi"), WingItem(symbol: "battery.100.bolt", label: "82%", tint: .accent)], musicPlaying: false, strip: nil)
    static let songSample = Activity.music(title: "Midnight City", artist: "M83")

    /// The margin of desktop drawn on either side of the notch.
    static let margin: CGFloat = 360

    static func scene(_ row: Row, geometry: NotchGeometry) -> Scene {
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - margin
        let regionWidth = notch.width + margin * 2
        let notchHeight = notch.height
        // Taken per row, so the glow's breath is where `listeningFor` puts it
        // however long the rows before took to draw.
        let now = Date()
        // The listening mark, as the app's own model gives it for this
        // shape after `listeningFor` seconds of listening.
        let mark: NeoListeningMark? = row.neo == .listening ? {
            var indicator = NeoListeningIndicator()
            indicator.update(listening: true, at: now.addingTimeInterval(-row.listeningFor))
            return indicator.mark(for: row.state, at: now, labelWidth: NotchHubApp.listeningLabelWidth)
        }() : nil
        let slot = mark?.slot ?? 0
        var content: IslandContentSize
        switch row.state {
        case .wings:
            let sides = IslandMetrics.wings(row.wings ?? WingStatus(), petSlot: PetLayout.barSlot + slot)
            content = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: sides.trail)
            content.wingLead = sides.lead
        case .compact:
            content = row.activity.map { IslandMetrics.compact($0, petSlot: PetLayout.barSlot + slot) } ?? .default
        default:
            content = .default
        }
        if row.state == .idle { content.petDock = row.dock ?? .home }
        content.listeningSlot = slot
        let frame = geometry.frame(for: row.state, content: content)
        let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
        // The pose as the brain gives it, started so that the wanted cel shows now.
        let petModel: PetRenderModel? = row.state == .neoPanel ? nil : {
            let id = row.neo.map(PetBrain.neoAnimation(for:)) ?? .sit
            let started = now.addingTimeInterval(-Double(row.frame) * id.animation.frameDuration - 0.001)
            return PetRenderModel(presentation: PetPresentation(
                mood: (row.neo ?? .idle) == .idle ? .idle : .neo, animation: id, startedAt: started,
                mirrored: row.state == .idle && row.dock?.side == .left
            ))
        }()
        let panelHeight = geometry.frame(for: .neoPanel, content: .default).height
        let rowHeight = row.state == .neoPanel ? panelHeight + 8 : max(44, NotchGeometry.expandedHeight + 8)
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
            listening: mark
        )
        .frame(width: regionWidth, height: rowHeight)
        .background(Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45))
        let pet = row.state == .neoPanel ? nil
            : PetLayout.placement(for: row.state, islandSize: frame.size, notchHeight: notchHeight, dock: content.petDock ?? .home)
        return Scene(view: AnyView(view), frame: frame, local: local, content: content, mark: mark, pet: pet, rowHeight: rowHeight)
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
        rows += [
            // Listening: the glow behind the pet, with the word beside it
            // for the first 1.5 s — in every shape the pet rides. Afterwards
            // each island is exactly as wide as it is without NEO.
            Row(name: "idle, listening t=0.5 s — the glow and the word", state: .idle, neo: .listening, listeningFor: 0.5),
            Row(name: "idle, listening t=3 s — the glow alone, no extra width", state: .idle, neo: .listening, listeningFor: 3),
            Row(name: "idle on the LEFT of the notch, listening t=0.5 s — mirrored, the word still toward the notch", state: .idle, neo: .listening,
                listeningFor: 0.5, dock: PetDock(side: .left, reach: PetLayout.idleDock)),
            Row(name: "idle on the LEFT of the notch, listening t=3 s", state: .idle, neo: .listening,
                listeningFor: 3, dock: PetDock(side: .left, reach: PetLayout.idleDock)),
            Row(name: "wings, listening t=0.5 s", state: .wings, neo: .listening, wings: wings, listeningFor: 0.5),
            Row(name: "wings, listening t=3 s", state: .wings, neo: .listening, wings: wings, listeningFor: 3),
            Row(name: "compact (volume), listening t=0.5 s", state: .compact, neo: .listening, activity: .volume(0.62), listeningFor: 0.5),
            Row(name: "compact (volume), listening t=3 s", state: .compact, neo: .listening, activity: .volume(0.62), listeningFor: 3),
            Row(name: "expanded (music), listening t=0.5 s", state: .expanded, neo: .listening, activity: song, listeningFor: 0.5),
            Row(name: "expanded (music), listening t=3 s", state: .expanded, neo: .listening, activity: song, listeningFor: 3),
            Row(name: "compact (volume), speaking", state: .compact, neo: .speaking, activity: .volume(0.62)),
            Row(name: "expanded (music), thinking", state: .expanded, neo: .thinking, activity: song),
            Row(name: "NEO panel (the chat, \(Int(NeoPanelLayout.standard.width))×\(Int(NeoPanelLayout.standard.height)) under the notch), speaking — no pet", state: .neoPanel, neo: .speaking),
        ]

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
            let (frame, local, mark) = (scene.frame, scene.local, scene.mark)
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
            context.saveGState()
            context.translateBy(x: 0, y: y + CGFloat(image.height))
            context.scaleBy(x: scale, y: -scale)
            context.addPath(NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: DesignTokens.radiusNotchTopFlare)
                .path(in: CGRect(x: notch.minX - regionMinX, y: 0, width: notch.width, height: notch.height)).cgPath)
            context.setFillColor(CGColor(srgbRed: 0.6, green: 0.05, blue: 0.05, alpha: 0.5))
            context.fillPath()
            context.restoreGState()
            var line = String(format: "row %d: %@ — island %.0f×%.0f", index, row.name, frame.width, frame.height)
            if let mark, let pet = scene.pet {
                // The island this row would be with NEO idle: once the word
                // has gone, listening must not have widened it at all.
                let plain = self.scene(Row(name: "", state: row.state, neo: .idle, activity: row.activity, wings: row.wings, dock: row.dock), geometry: geometry).frame
                let glow = NeoListeningLayout.glowFrame(behind: pet, scale: NeoListeningLayout.glowScaleRange.upperBound)
                line += String(format: " — glow %.0f pt, +%.0f pt wide", NeoListeningLayout.glowDiameter(petSize: pet.size), frame.width - plain.width)
                line += CGRect(origin: .zero, size: frame.size).contains(glow) ? ", inside the island" : ", PAST THE ISLAND'S EDGE"
                if mark.showsLabel {
                    let rect = NeoListeningLayout.labelFrame(mark, beside: pet).offsetBy(dx: local.minX, dy: 0)
                    let notchRect = CGRect(x: notch.minX - regionMinX, y: 0, width: notch.width, height: notch.height)
                    line += String(format: ", the word %.0f pt", mark.labelWidth) + (rect.intersects(notchRect) ? " — UNDER THE NOTCH" : " — clear of the notch")
                }
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
    /// real island and enlarged — at the top of a breath and at the bottom of
    /// one, in the notch strip (the 16-pt fox on its idle dock) and in the
    /// expanded island (the 32-pt fox) — beside the same fox with NEO idle.
    static func renderGlowZoom(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let regionMinX = geometry.notchFrame.minX - margin
        // Whole breaths after the word has gone: brightest at 0.4 s into a
        // breath, dimmest at 1.2 s.
        let period = NeoListeningLayout.breathPeriod
        let brightest = period * 1.25
        let dimmest = period * 1.75
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
                (String(format: "listening, brightest (t = %.1f s)", brightest), .listening, brightest),
                (String(format: "listening, dimmest (t = %.1f s)", dimmest), .listening, dimmest),
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
        print(String(format: "glow %.0f pt around the 16-pt fox, %.0f pt around the 32-pt one; opacity %.2f–%.2f, scale %.2f–%.2f, one breath %.1f s",
                     NeoListeningLayout.glowDiameter(petSize: 16), NeoListeningLayout.glowDiameter(petSize: 32),
                     NeoListeningLayout.glowOpacityRange.lowerBound, NeoListeningLayout.glowOpacityRange.upperBound,
                     NeoListeningLayout.glowScaleRange.lowerBound, NeoListeningLayout.glowScaleRange.upperBound, period))
        print(file.path)
        return 0
    }
}
