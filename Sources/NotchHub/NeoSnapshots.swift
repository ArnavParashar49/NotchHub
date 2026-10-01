import AppKit
import NotchHubCore
import NotchHubOrbs
import SwiftUI
import UniformTypeIdentifiers

/// `--neo-snapshots DIR`: the real `IslandView` with NEO's lane, rendered
/// offscreen with `ImageRenderer` in each island shape and NEO state, so the
/// lane's placement, width, mask and orb can be checked without a core or a
/// screen recording. The hardware notch is drawn over it in translucent red.
/// The last row is NEO's panel (its chat hangs down from the notch) with a
/// stand-in for the page: a web view cannot be rendered offscreen.
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
            let neo: NeoLaneContent?
            var activity: Activity? = nil
            var wings: WingStatus? = nil
            var pet: PetDock? = nil
        }
        let rows: [Row] = [
            Row(name: "idle, tucked in", state: .idle, neo: nil),
            Row(name: "idle, connecting", state: .idle, neo: NeoLaneContent(state: .connecting, line: NeoState.connecting.label)),
            Row(name: "idle, listening (no words yet)", state: .idle, neo: NeoLaneContent(state: .listening, line: NeoState.listening.label)),
            Row(name: "idle, listening", state: .idle, neo: NeoLaneContent(state: .listening, line: "what's the weather like in Paris this weekend", isTranscript: true)),
            Row(name: "idle, thinking", state: .idle, neo: NeoLaneContent(state: .thinking, line: NeoState.thinking.label)),
            Row(name: "idle, searching", state: .idle, neo: NeoLaneContent(state: .searching, line: NeoState.searching.label)),
            Row(name: "idle, speaking", state: .idle, neo: NeoLaneContent(state: .speaking, line: "Paris looks mild this weekend: sunny on Saturday, around 19 degrees.", isTranscript: true)),
            Row(name: "idle, confirming", state: .idle, neo: NeoLaneContent(state: .confirming, line: NeoState.confirming.label)),
            Row(name: "idle, speaking, pet home", state: .idle, neo: NeoLaneContent(state: .speaking, line: "Done.", isTranscript: true), pet: .home),
            // As the coordinator sizes it: a pet visiting the left steps into the notch.
            Row(name: "idle, working, pet visiting the left (hidden)", state: .idle, neo: NeoLaneContent(state: .working, line: NeoState.working.label), pet: PetDock(side: .left, reach: 0)),
            Row(name: "wings, thinking", state: .wings, neo: NeoLaneContent(state: .thinking, line: NeoState.thinking.label),
                wings: WingStatus(left: WingItem(symbol: "safari", label: "Safari"), right: [WingItem(symbol: "wifi", label: "Wi-Fi"), WingItem(symbol: "battery.100.bolt", label: "82%", tint: .accent)], musicPlaying: false, strip: nil)),
            Row(name: "compact (volume), speaking", state: .compact, neo: NeoLaneContent(state: .speaking, line: "Turning it down.", isTranscript: true), activity: .volume(0.62)),
            Row(name: "expanded (music), listening", state: .expanded, neo: NeoLaneContent(state: .listening, line: "play something quieter", isTranscript: true), activity: .music(title: "Midnight City", artist: "M83")),
            Row(name: "NEO panel (the chat, 420×520 under the notch), speaking", state: .neoPanel, neo: NeoLaneContent(state: .speaking, line: "Paris looks mild this weekend.", isTranscript: true)),
        ]

        let panelHeight = geometry.frame(for: .neoPanel, content: .default).height
        let height: CGFloat = max(44, NotchGeometry.expandedHeight + 8)
        let scale: CGFloat = 2
        let rowHeight = Int(height * scale) + 6
        // Row heights: the bars' standard height, the panel its own.
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
                let sides = IslandMetrics.wings(row.wings ?? WingStatus(), petSlot: 0)
                content = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: sides.trail)
                content.wingLead = sides.lead
            case .compact:
                content = row.activity.map { IslandMetrics.compact($0) } ?? .default
            default:
                content = .default
            }
            content.petDock = row.pet
            if let neo = row.neo {
                content.neoLead = NeoLaneLayout.width(notchHeight: notchHeight)
                switch row.state {
                case .idle, .wings, .compact: break
                default:
                    let surface = geometry.frame(for: row.state, content: content).width
                    content.neoLead = NeoLaneLayout.fitted(width: content.neoLead, surfaceWidth: surface, notchWidth: notch.width)
                }
            }
            let frame = geometry.frame(for: row.state, content: content)
            let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
            let petModel = row.pet.map { dock in
                PetRenderModel(presentation: PetPresentation(mood: .idle, animation: .sit, startedAt: now, mirrored: dock.side == .left))
            }
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
                notchWidth: notch.width, contentSize: content, panelContent: placeholder, surfaceVisible: true, pet: petModel, hasNotch: true,
                neo: row.neo, notchLeadingX: notch.minX - regionMinX
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
            print(String(format: "row %d: %@ — lane %.0f pt, island %.0f×%.0f", index, row.name, content.neoLead, frame.width, frame.height))
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
