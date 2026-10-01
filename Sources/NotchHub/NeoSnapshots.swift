import AppKit
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--neo-snapshots DIR`: the real `IslandView` with the pet posing as NEO,
/// rendered offscreen with `ImageRenderer` in each of NEO's states and in
/// the island shapes it can be in, so each pose can be checked without a
/// core or a screen recording. Every row's island is exactly the pre-NEO
/// island — the pet's pose is all that changes. The hardware notch is drawn
/// over it in translucent red. The last row is NEO's panel (its chat hangs
/// down from the notch, with no pet) with a stand-in for the page: a web
/// view cannot be rendered offscreen.
@MainActor
enum NeoSnapshots {

    static func render(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - 360
        let regionWidth = notch.width + 720
        let now = Date()
        let notchHeight = notch.height

        struct Row {
            let name: String
            let state: IslandState
            let neo: NeoState?
            var activity: Activity? = nil
            var wings: WingStatus? = nil
            /// Which frame of the pose to draw (its loop's n-th cel).
            var frame: Int = 0
        }
        var rows: [Row] = [Row(name: "idle, NEO ready (the pet's own life)", state: .idle, neo: .idle)]
        for state in NeoState.allCases where state != .idle {
            let animation = PetBrain.neoAnimation(for: state).animation
            let frames = max(1, min(animation.frames.count, animation.loops ? 4 : 2))
            for frame in 0..<frames {
                rows.append(Row(name: "idle, \(state.rawValue) — \(PetBrain.neoAnimation(for: state).rawValue) cel \(frame)", state: .idle, neo: state, frame: frame))
            }
        }
        rows += [
            Row(name: "wings, listening", state: .wings, neo: .listening,
                wings: WingStatus(left: WingItem(symbol: "safari", label: "Safari"), right: [WingItem(symbol: "wifi", label: "Wi-Fi"), WingItem(symbol: "battery.100.bolt", label: "82%", tint: .accent)], musicPlaying: false, strip: nil)),
            Row(name: "compact (volume), speaking", state: .compact, neo: .speaking, activity: .volume(0.62)),
            Row(name: "expanded (music), thinking", state: .expanded, neo: .thinking, activity: .music(title: "Midnight City", artist: "M83")),
            Row(name: "NEO panel (the chat, 420×520 under the notch), speaking — no pet", state: .neoPanel, neo: .speaking),
        ]

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
            var content: IslandContentSize
            switch row.state {
            case .wings:
                let sides = IslandMetrics.wings(row.wings ?? WingStatus(), petSlot: PetLayout.barSlot)
                content = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: sides.trail)
                content.wingLead = sides.lead
            case .compact:
                content = row.activity.map { IslandMetrics.compact($0, petSlot: PetLayout.barSlot) } ?? .default
            default:
                content = .default
            }
            if row.state == .idle { content.petDock = .home }
            let frame = geometry.frame(for: row.state, content: content)
            let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
            // The pose as the brain gives it, started so that the wanted cel shows now.
            let petModel: PetRenderModel? = row.state == .neoPanel ? nil : {
                let id = row.neo.map(PetBrain.neoAnimation(for:)) ?? .sit
                let started = now.addingTimeInterval(-Double(row.frame) * id.animation.frameDuration - 0.001)
                return PetRenderModel(presentation: PetPresentation(mood: (row.neo ?? .idle) == .idle ? .idle : .neo, animation: id, startedAt: started))
            }()
            let rowHeightPoints = row.state == .neoPanel ? panelHeight + 8 : height
            let placeholder: AnyView? = row.state == .neoPanel
                ? AnyView(VStack(spacing: 8) {
                    Text("NEO's chat page (a WKWebView, served from neo://app/)").font(.system(size: 12, weight: .semibold))
                    Text("transcript · confirm buttons · browser, camera and song cards").font(.system(size: 11))
                }.foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity))
                : nil
            let view = IslandView(
                current: row.activity, stackCount: 0, state: row.state, localFrame: local, cornerRadius: 10,
                notchInset: notchHeight, isIdle: row.state == .idle, wingStatus: row.wings ?? WingStatus(),
                notchWidth: notch.width, contentSize: content, panelContent: placeholder, surfaceVisible: true, pet: petModel, hasNotch: true
            )
            .frame(width: regionWidth, height: rowHeightPoints)
            .background(Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45))
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
            print(String(format: "row %d: %@ — island %.0f×%.0f", index, row.name, frame.width, frame.height))
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("neo-snapshots.png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(file.path)
        return 0
    }
}
