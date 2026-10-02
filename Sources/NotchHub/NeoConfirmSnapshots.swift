import AppKit
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--neo-confirm-snapshot DIR`: NEO's Allow / Cancel under the notch, drawn
/// by the real `IslandView` at the real geometry and written to
/// `DIR/notch-confirm.png` — what was there before (the fox asking with its
/// "!" on the idle dock), the buttons as they are seen (the hardware notch
/// in black over the strip), the same with the hit targets outlined in green
/// and the notch translucent (so anything hidden behind the cutout shows),
/// the cursor on each button, and the fox on the left of the notch.
@MainActor
enum NeoConfirmSnapshots {

    struct Row {
        let caption: String
        let state: IslandState
        var hovered: NeoConfirmChoice? = nil
        var dock: PetDock = .home
        /// The hardware notch drawn opaque (as seen) or translucent red.
        var notchOpaque = true
        var outlines = false
    }

    static let card = NeoConfirmCard(
        actionID: "trash:snapshot", tool: "trash", summary: "move report.pdf to the Trash",
        detail: "/Users/you/Documents/report.pdf"
    )
    static let margin: CGFloat = 150

    static func render(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - margin
        let regionWidth = notch.width + margin * 2
        let confirm = geometry.frame(for: .neoConfirm, content: .default)
        let rowHeight = confirm.height + 14
        let scale: CGFloat = 3

        let rows = [
            Row(caption: "before: NEO asks — the fox's “!” on its idle dock", state: .idle),
            Row(caption: "NEO needs an OK: the island pops down for Allow and Cancel — nothing else", state: .neoConfirm),
            Row(caption: "the hit targets (green), the notch translucent: nothing hides behind it", state: .neoConfirm, notchOpaque: false, outlines: true),
            Row(caption: "the cursor on Allow", state: .neoConfirm, hovered: .allow),
            Row(caption: "the cursor on Cancel", state: .neoConfirm, hovered: .cancel),
            Row(caption: "the fox on the left of the notch", state: .neoConfirm, dock: PetDock(side: .left, reach: PetLayout.idleDock)),
        ]

        var images: [(Row, CGImage)] = []
        for row in rows {
            var content = IslandContentSize.default
            content.petDock = row.dock
            let frame = geometry.frame(for: row.state, content: content)
            let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
            let animation = PetBrain.neoAnimation(for: .confirming)
            let pet = PetRenderModel(presentation: PetPresentation(
                mood: .neo, animation: animation, startedAt: Date().addingTimeInterval(-0.001),
                mirrored: row.dock.side == .left
            ))
            let panel: AnyView? = row.state == .neoConfirm
                ? AnyView(NeoConfirmView(card: card, hovered: row.hovered))
                : nil
            let targets = row.outlines
                ? NeoConfirmLayout.buttons(in: frame, notchInset: notch.height).map { target in
                    CGRect(x: target.rect.minX - regionMinX, y: frame.maxY - target.rect.maxY, width: target.rect.width, height: target.rect.height)
                }
                : []
            let view = IslandView(
                current: nil, stackCount: 0, state: row.state, localFrame: local, cornerRadius: 10,
                notchInset: notch.height, isIdle: row.state == .idle, notchWidth: notch.width, contentSize: content,
                panelContent: panel, surfaceVisible: true, pet: pet, hasNotch: true
            )
            .frame(width: regionWidth, height: rowHeight)
            .background(Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45))
            .overlay(alignment: .topLeading) {
                // The hardware notch.
                NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: DesignTokens.radiusNotchTopFlare)
                    .fill(row.notchOpaque ? Color.black : Color(.sRGB, red: 0.6, green: 0.05, blue: 0.05).opacity(0.5))
                    .frame(width: notch.width, height: notch.height)
                    .offset(x: notch.minX - regionMinX)
            }
            .overlay(alignment: .topLeading) {
                ForEach(Array(targets.enumerated()), id: \.offset) { _, rect in
                    Rectangle()
                        .strokeBorder(Color(.sRGB, red: 0.2, green: 1, blue: 0.4), lineWidth: 0.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage else {
                print("\(row.caption): render failed")
                return 1
            }
            images.append((row, image))
            print(String(format: "%@ — island %.0f×%.0f", row.caption, frame.width, frame.height))
        }

        let sheet = VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 5) {
                    Image(decorative: entry.1, scale: scale)
                    Text(entry.0.caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize()
                }
            }
        }
        .padding(16)
        .background(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.11))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = scale
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("notch-confirm.png")
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        let buttons = NeoConfirmLayout.buttons(in: confirm, notchInset: notch.height)
        print(String(format: "surface %.0f×%.0f (the notch is %.0f×%.0f); buttons %.0f×%.0f each, %.0f pt apart; Allow counts after %.1f s",
                     confirm.width, confirm.height, notch.width, notch.height,
                     buttons[0].rect.width, buttons[0].rect.height, NeoConfirmLayout.spacing, NeoConfirmModel.allowGuard))
        print(file.path)
        return 0
    }
}
