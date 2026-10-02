import AppKit
import CoreGraphics
import Foundation
import ImageIO
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--pet-storyboard DIR [SEED]`: renders the pet's mischief frame by frame, the
/// way the idle notch shows it — the dock springing, the pet moving — with the
/// hardware notch drawn over it in translucent red, so whatever hides beneath
/// it can still be inspected. Headless: no window, no Screen Recording.
@MainActor
enum PetStoryboard {

    static let scale: CGFloat = 3
    static let margin: CGFloat = 56
    static let columns = 5
    static let frameStep: TimeInterval = 1.0 / 60
    static let sampleEvery = 3

    struct Sample {
        let time: TimeInterval
        let dock: PetDock
        let shownReach: CGFloat
        let presentation: PetPresentation
        let elapsed: TimeInterval
        let beat: String
    }

    static func run(directory: String, seed: UInt64) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var context = PetContext()
        context.canRoam = true
        context.mischief = true
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        var scenes: [(name: String, brain: PetBrain, start: Date)] = []
        for kind in [PetMischief.hideAndSeek, .crossOver, .zoomies] {
            var brain = PetBrain(now: start, seed: seed)
            brain.startMischief(kind, now: start)
            scenes.append((kind.rawValue, brain, start))
        }
        // A visit to the left, then the way home.
        var away = PetBrain(now: start, seed: seed)
        away.startMischief(.crossOver, now: start)
        var t = start
        while away.mischief != nil, let next = away.nextWakeup(context: context, now: t) {
            t = next
            away.update(context, now: t)
        }
        away.startMischief(.returnHome, now: t)
        scenes.append(("returnHome", away, t))

        for scene in scenes {
            var brain = scene.brain
            let samples = simulate(&brain, from: scene.start, context: context)
            let url = folder.appendingPathComponent("pet-\(scene.name)-\(seed).png")
            draw(samples, geometry: geometry, to: url)
            print("\(scene.name): \(samples.count) cells → \(url.path)")
            for (index, sample) in samples.enumerated() {
                print(String(format: "  %02d t=%.1fs %@ dock=%@/%.0f shown=%.1f", index, sample.time, sample.beat,
                             sample.dock.side.rawValue, sample.dock.reach, sample.shownReach))
            }
        }
        return 0
    }

    /// Steps the brain at 30 fps, following its dock with the island's springs.
    static func simulate(_ brain: inout PetBrain, from start: Date, context: PetContext) -> [Sample] {
        var samples: [Sample] = []
        var side = brain.dock.side
        var from = PetDock.home.reach
        var to = brain.dock.reach
        var springStart = start
        var spring = (response: 0.40, damping: 0.84)
        var ended: Date?
        var tick = 0
        var now = start
        while now.timeIntervalSince(start) < 20 {
            brain.update(context, now: now)
            let dock = brain.dock
            if dock.side != side || dock.reach != to {
                let shown = side == dock.side ? reach(from, to, now.timeIntervalSince(springStart), spring) : 0
                spring = shown < dock.reach ? (0.40, 0.84) : (shown > dock.reach ? (0.50, 1.0) : (0.44, 0.92))
                from = shown
                to = dock.reach
                side = dock.side
                springStart = now
            }
            if tick % sampleEvery == 0 {
                let beat = brain.mischiefStepIndex.map { "\($0 + 1)/\(brain.mischiefSteps.count) \(brain.presentation.animation.rawValue)" }
                    ?? brain.presentation.animation.rawValue
                samples.append(Sample(
                    time: now.timeIntervalSince(start),
                    dock: dock,
                    shownReach: reach(from, to, now.timeIntervalSince(springStart), spring),
                    presentation: brain.presentation,
                    elapsed: now.timeIntervalSince(brain.presentation.startedAt),
                    beat: beat
                ))
            }
            if brain.mischief == nil { ended = ended ?? now }
            if let ended, now.timeIntervalSince(ended) > 0.5 { break }
            tick += 1
            now = now.addingTimeInterval(frameStep)
        }
        return samples
    }

    /// SwiftUI's `spring(response:dampingFraction:)`, `t` seconds in.
    static func reach(_ from: CGFloat, _ to: CGFloat, _ t: TimeInterval, _ spring: (response: Double, damping: Double)) -> CGFloat {
        guard t > 0 else { return from }
        let w0 = 2 * Double.pi / spring.response
        let progress: Double
        if spring.damping >= 1 {
            progress = 1 - exp(-w0 * t) * (1 + w0 * t)
        } else {
            let wd = w0 * (1 - spring.damping * spring.damping).squareRoot()
            progress = 1 - exp(-spring.damping * w0 * t) * (cos(wd * t) + spring.damping * w0 / wd * sin(wd * t))
        }
        return from + (to - from) * CGFloat(progress)
    }

    static func draw(_ samples: [Sample], geometry: NotchGeometry, to url: URL) {
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - margin
        let cellWidth = (notch.width + margin * 2) * scale
        let cellHeight = (notch.height + 10) * scale
        let pad: CGFloat = 8
        let rows = max(1, (samples.count + columns - 1) / columns)
        let width = Int(CGFloat(columns) * (cellWidth + pad) + pad)
        let height = Int(CGFloat(rows) * (cellHeight + pad) + pad)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // Top-left origin, like SwiftUI.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (index, sample) in samples.enumerated() {
            context.saveGState()
            context.translateBy(x: pad + CGFloat(index % columns) * (cellWidth + pad), y: pad + CGFloat(index / columns) * (cellHeight + pad))
            context.scaleBy(x: scale, y: scale)
            let cell = CGRect(x: 0, y: 0, width: notch.width + margin * 2, height: notch.height + 10)
            // Menu bar and desktop.
            context.setFillColor(CGColor(srgbRed: 0.42, green: 0.42, blue: 0.45, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: cell.width, height: notch.height))
            context.setFillColor(CGColor(srgbRed: 0.24, green: 0.25, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: 0, y: notch.height, width: cell.width, height: 10))

            // The island, sized by the springing dock, shaped for its target.
            // Sized AND placed from the springing dock, as IslandView does.
            let shownDock = PetDock(side: sample.dock.side, reach: sample.shownReach)
            var content = IslandContentSize.default
            content.petDock = shownDock
            let frame = geometry.frame(for: .idle, content: content)
            let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
            let island = NotchShape.surface(islandRadius: DesignTokens.radiusIslandBottom, idleDock: sample.dock).path(in: local).cgPath
            context.addPath(island)
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fillPath()

            // The pet, masked to the island.
            context.saveGState()
            context.addPath(island)
            context.clip()
            if let placement = PetLayout.placement(for: .idle, islandSize: frame.size, notchHeight: notch.height, dock: shownDock) {
                let animation = sample.presentation.animation.animation
                let frameIndex = animation.frameIndex(at: sample.elapsed)
                let mirrored = sample.presentation.mirrored
                let offset = animation.offset(forFrame: frameIndex)
                if let art = PetFrame.named(PetFrame.name(animation.frames[frameIndex], mirrored: mirrored)) {
                    let x = local.minX + placement.origin.x + CGFloat(mirrored ? -offset.dx : offset.dx)
                    let y = placement.origin.y + CGFloat(offset.dy)
                    for run in art.runs {
                        context.setFillColor(CGColor(
                            srgbRed: CGFloat((run.color >> 16) & 0xFF) / 255,
                            green: CGFloat((run.color >> 8) & 0xFF) / 255,
                            blue: CGFloat(run.color & 0xFF) / 255,
                            alpha: 1
                        ))
                        context.fill(CGRect(x: x + CGFloat(run.x), y: y + CGFloat(run.y), width: CGFloat(run.length), height: 1))
                    }
                }
            }
            context.restoreGState()

            // The hardware notch on top: translucent red, so what hides shows.
            let hardware = CGRect(x: notch.minX - regionMinX, y: 0, width: notch.width, height: notch.height)
            context.addPath(hardwareNotch.path(in: hardware).cgPath)
            context.setFillColor(CGColor(srgbRed: 0.6, green: 0.05, blue: 0.05, alpha: 0.5))
            context.fillPath()
            context.restoreGState()
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// `--pet-snapshots DIR`: the real `IslandView`, rendered offscreen with
    /// `ImageRenderer` for each dock shape and pose, so the SwiftUI pet layer —
    /// anchors, offsets, mirroring, the mask — can be checked without Screen
    /// Recording. The hardware notch is drawn over it in translucent red.
    static func snapshots(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - 140
        let regionWidth = notch.width + 280
        let height: CGFloat = 44
        let now = Date()
        let full = PetLayout.idleDock
        let peek = PetLayout.peekReach
        let cases: [(name: String, state: IslandState, dock: PetDock, animation: PetAnimationID, elapsed: TimeInterval)] = [
            ("home sit", .idle, .home, .sit, 0),
            ("dashIn 0.36s", .idle, .home, .dashIn, 0.36),
            ("hidden, dock closed", .idle, PetDock(side: .right, reach: 0), .hidden, 0),
            ("tailPeek 1.0s", .idle, PetDock(side: .right, reach: peek), .tailPeek, 1.0),
            ("peek 1.0s", .idle, PetDock(side: .right, reach: peek), .peek, 1.0),
            ("peek left 2.3s", .idle, PetDock(side: .left, reach: peek), .peek, 2.3),
            ("popOut left 0.25s", .idle, PetDock(side: .left, reach: full), .popOut, 0.25),
            ("dashOut left 0.3s", .idle, PetDock(side: .left, reach: full), .dashOut, 0.3),
            ("away left blep", .idle, PetDock(side: .left, reach: full), .blep, 0.2),
            ("pounce 0.75s", .idle, .home, .pounce, 0.75),
            ("hop 0.21s", .idle, .home, .hop, 0.21),
            ("wings sit", .wings, .home, .sit, 0),
            ("compact sit", .compact, .home, .sit, 0),
        ]
        // A look and a hat per row, so hats and looks are checked on every shape.
        let styles: [(PetLook, PetHat?)] = [
            (.fox, .party), (.fox, .witch), (.fox, .santa), (.fox, .flowers), (.arctic, .bunny), (.silver, .turkey),
            (.sand, .lunar), (.fox, .marigold), (.fox, .hearts), (.fox, .shamrock), (.arctic, .party), (.silver, .santa), (.sand, .witch),
        ]
        let scale: CGFloat = 3
        let rowHeight = Int(height * scale) + 6
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(regionWidth * scale), height: rowHeight * cases.count, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Int(regionWidth * scale), height: rowHeight * cases.count))

        for (index, item) in cases.enumerated() {
            var content: IslandContentSize
            switch item.state {
            case .wings: content = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: 120)
            case .compact: content = IslandContentSize(compactLead: 48, compactTrail: 110, wingSide: 0)
            default: content = .default
            }
            content.petDock = item.dock
            let frame = geometry.frame(for: item.state, content: content)
            let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
            let presentation = PetPresentation(mood: .mischief, animation: item.animation,
                                               startedAt: now.addingTimeInterval(-item.elapsed), mirrored: item.dock.side == .left)
            let view = IslandView(
                current: nil, stackCount: 0, state: item.state, localFrame: local, cornerRadius: 10,
                notchInset: notch.height, isIdle: item.state == .idle, notchWidth: notch.width, contentSize: content,
                surfaceVisible: true, pet: PetRenderModel(presentation: presentation, look: styles[index % styles.count].0, hat: styles[index % styles.count].1),
                hasNotch: true
            )
            .frame(width: regionWidth, height: height)
            .background(Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45))
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage else {
                print("\(item.name): render failed")
                continue
            }
            // CGContext is bottom-left: row 0 at the top.
            let y = CGFloat(rowHeight * (cases.count - 1 - index))
            context.draw(image, in: CGRect(x: 0, y: y, width: CGFloat(image.width), height: CGFloat(image.height)))
            // The hardware notch's outline on top (flipped into this bottom-left context).
            context.saveGState()
            context.translateBy(x: 0, y: y + CGFloat(image.height))
            context.scaleBy(x: scale, y: -scale)
            context.addPath(hardwareNotch.path(in: CGRect(x: notch.minX - regionMinX, y: 0, width: notch.width, height: notch.height)).cgPath)
            context.setFillColor(CGColor(srgbRed: 0.6, green: 0.05, blue: 0.05, alpha: 0.5))
            context.fillPath()
            context.restoreGState()
            print(String(format: "row %d: %@", index, item.name))
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("pet-snapshots.png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(file.path)
        return 0
    }

    /// `--pet-panel-snapshots DIR`: the real island showing the pet's panel —
    /// for a few looks, hats and poses — with every hit target from
    /// `PetPanelLayout` outlined in green on top, so the drawing and the click
    /// targets can be checked against each other. The panel is always centred
    /// on the notch, so the rows differ only in what the pet is wearing/doing.
    static func panelSnapshots(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - 300
        let regionWidth = notch.width + 600
        let regionTop = notch.maxY
        let height: CGFloat = 110
        let scale: CGFloat = 3
        let now = Date()
        let cases: [(name: String, look: PetLook, hat: PetHatChoice, focusing: Bool, animation: PetAnimationID)] = [
            ("fox, seasonal, waving", .fox, .seasonal, false, .hiWave),
            ("arctic, party, leaning", .arctic, .party, false, .leanLeft),
            ("silver, witch, focusing, stroked", .silver, .witch, true, .stroke),
            ("sand, santa, happy", .sand, .santa, false, .happy),
        ]
        let rowHeight = Int(height * scale) + 6
        let width = Int(regionWidth * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: rowHeight * cases.count, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: rowHeight * cases.count))

        let content = IslandContentSize.default
        for (index, item) in cases.enumerated() {
            let frame = geometry.frame(for: .skin, content: content)
            let local = CGRect(x: frame.minX - regionMinX, y: regionTop - frame.maxY, width: frame.width, height: frame.height)
            let presentation = PetPresentation(mood: .interaction, animation: item.animation, startedAt: now.addingTimeInterval(-0.2))
            let contentLeading = PetPanelLayout.contentMinX(in: frame) - frame.minX
            let panel = PetPanelView(presentation: presentation, look: item.look,
                                     hat: item.hat.hat(on: now), hatChoice: item.hat, isFocusing: item.focusing,
                                     contentLeading: contentLeading)
            let view = IslandView(
                current: nil, stackCount: 0, state: .skin, localFrame: local, cornerRadius: 10,
                notchInset: notch.height, isIdle: false, notchWidth: notch.width, contentSize: content,
                panelContent: AnyView(panel), surfaceVisible: true, pet: nil, hasNotch: true
            )
            .frame(width: regionWidth, height: height)
            .background(Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45))
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage else {
                print("\(item.name): render failed")
                continue
            }
            let rowBottom = CGFloat(rowHeight * (cases.count - 1 - index))
            context.draw(image, in: CGRect(x: 0, y: rowBottom, width: CGFloat(image.width), height: CGFloat(image.height)))

            // Hit targets, converted from screen (AppKit) to this row.
            let layout = PetPanelLayout.layout(in: frame, notchInset: notch.height)
            // The hardware notch, translucent, over the island.
            let hardware = CGRect(x: (notch.minX - regionMinX) * scale, y: rowBottom + CGFloat(image.height) - notch.height * scale,
                                  width: notch.width * scale, height: notch.height * scale)
            context.setFillColor(CGColor(srgbRed: 0.6, green: 0.05, blue: 0.05, alpha: 0.45))
            context.fill(hardware)
            let targets = [layout.pet, layout.hat, layout.more] + layout.actions.map(\.rect) + layout.looks.map(\.rect)
            context.setStrokeColor(CGColor(srgbRed: 0.2, green: 1, blue: 0.4, alpha: 0.9))
            context.setLineWidth(1)
            for rect in targets {
                let topInRow = (regionTop - rect.maxY) * scale
                let cg = CGRect(x: (rect.minX - regionMinX) * scale, y: rowBottom + CGFloat(image.height) - topInRow - rect.height * scale,
                                width: rect.width * scale, height: rect.height * scale)
                context.stroke(cg.insetBy(dx: 0.5, dy: 0.5))
            }
            print(String(format: "row %d: %@ (panel %.0f x %.0f)", index, item.name, frame.width, frame.height))
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("pet-panel-snapshots.png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(file.path)
        return 0
    }

    /// `--app-snapshots DIR`: a browser's hover strip and click panel, drawn by
    /// the real island with their hit targets outlined in green.
    static func appSnapshots(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - 300
        let regionWidth = notch.width + 600
        let regionTop = notch.maxY
        let scale: CGFloat = 3
        let appName = "Google Chrome"
        let icon = NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app").tiffRepresentation
        let tabs = [
            BrowserTab(index: 3, title: "Pull requests · ArnavParashar49/NotchHub", host: "github.com"),
            BrowserTab(index: 4, title: "Swift Testing | Apple Developer Documentation", host: "developer.apple.com"),
            BrowserTab(index: 5, title: "YouTube", host: "youtube.com"),
        ]
        let browser = BrowserContext(title: tabs[1].title, host: tabs[1].host, tabs: tabs, activeIndex: 4)
        let status = WingStatus(left: WingItem(symbol: "app.fill", iconData: icon),
                                strip: AppStrip(label: AppStripLabel.shortAppName(appName), trailing: .browserControls))
        let pet = PetRenderModel(presentation: PetPresentation(mood: .idle, animation: .sit, startedAt: Date()), look: .fox, hat: nil)

        var wingsContent = IslandContentSize.default
        let sides = IslandMetrics.wings(status, petSlot: PetLayout.barSlot)
        wingsContent.wingSide = sides.trail
        wingsContent.wingLead = sides.lead
        let wingsFrame = geometry.frame(for: .wings, content: wingsContent)
        // A plain app: its icon on the left, status glyphs on the right.
        let plainStatus = WingStatus(left: WingItem(symbol: "app.fill", iconData: icon),
                                     right: [WingItem(symbol: "wifi"), WingItem(symbol: "sun.max.fill")])
        var plainContent = IslandContentSize.default
        let plainSides = IslandMetrics.wings(plainStatus, petSlot: PetLayout.barSlot)
        plainContent.wingSide = plainSides.trail
        plainContent.wingLead = plainSides.lead
        let plainFrame = geometry.frame(for: .wings, content: plainContent)
        let panelFrame = geometry.frame(for: .appPanel, content: .default)
        // The hovered rows show the travelling highlight resting on a segment,
        // so the drawn hover state can be checked against the hit geometry.
        let rows: [(state: IslandState, frame: CGRect, content: IslandContentSize, height: CGFloat, status: WingStatus, hovered: IslandControl?)] = [
            (.wings, plainFrame, plainContent, 60, plainStatus, nil),
            (.wings, wingsFrame, wingsContent, 60, status, nil),
            (.wings, wingsFrame, wingsContent, 60, status, .wingBrowser(.back)),
            (.wings, wingsFrame, wingsContent, 60, status, .wingBrowser(.newTab)),
            (.appPanel, panelFrame, .default, panelFrame.height + 20, status, nil),
            (.appPanel, panelFrame, .default, panelFrame.height + 20, status, .appPanel(.browser(.reload))),
            (.appPanel, panelFrame, .default, panelFrame.height + 20, status, .appPanel(.browser(.selectTab(5)))),
        ]
        let rowHeights = rows.map { Int($0.height * scale) + 6 }
        let width = Int(regionWidth * scale)
        let total = rowHeights.reduce(0, +)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: total))

        var rowTop = total
        for row in rows {
            let local = CGRect(x: row.frame.minX - regionMinX, y: regionTop - row.frame.maxY, width: row.frame.width, height: row.frame.height)
            let panel: AnyView? = row.state == .appPanel
                ? AnyView(BrowserPanelView(notchInset: notch.height, appName: appName, iconData: icon,
                                           browser: browser, hovered: row.hovered))
                : nil
            let view = IslandView(
                current: nil, stackCount: 0, state: row.state, localFrame: local, cornerRadius: 10,
                notchInset: notch.height, isIdle: false, wingStatus: row.status, notchWidth: notch.width, contentSize: row.content,
                panelContent: panel, hoveredControl: row.hovered, surfaceVisible: true, pet: pet, hasNotch: true
            )
            .frame(width: regionWidth, height: row.height)
            .background(Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45))
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage else { return 1 }
            let rowBottom = CGFloat(rowTop) - CGFloat(image.height)
            context.draw(image, in: CGRect(x: 0, y: rowBottom, width: CGFloat(image.width), height: CGFloat(image.height)))

            let targets: [CGRect]
            if row.state == .wings {
                targets = WingControlLayout.browserButtons(in: row.frame, notchWidth: notch.width, inset: DesignTokens.wingInset,
                                                           trailingReserve: PetLayout.barSlot, lead: row.content.wingLead)
                    .filter { _ in row.status.strip != nil }.map(\.rect)
            } else {
                targets = AppPanelLayout.actions(in: row.frame, notchInset: notch.height, browserTabs: browser.nearbyTabs(limit: AppPanelLayout.maxTabRows)).map(\.rect)
            }
            context.setStrokeColor(CGColor(srgbRed: 0.2, green: 1, blue: 0.4, alpha: 0.9))
            context.setLineWidth(1)
            for rect in targets {
                let topInRow = (regionTop - rect.maxY) * scale
                let cg = CGRect(x: (rect.minX - regionMinX) * scale, y: rowBottom + CGFloat(image.height) - topInRow - rect.height * scale,
                                width: rect.width * scale, height: rect.height * scale)
                context.stroke(cg.insetBy(dx: 0.5, dy: 0.5))
            }
            print(String(format: "%@: %.0f x %.0f", String(describing: row.state), row.frame.width, row.frame.height))
            rowTop -= Int(row.height * scale) + 6
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("app-snapshots.png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(file.path)
        return 0
    }

    /// The hardware notch's outline, as the design tokens model it.
    static let hardwareNotch = NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: DesignTokens.radiusNotchTopFlare)
}
