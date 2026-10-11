import AppKit
import ImageIO
import NotchHubCore
import SwiftUI
import UniformTypeIdentifiers

/// `--pet-custom-snapshots DIR`: one contact sheet, `DIR/pet-custom.png`, of
/// everything the pet's page of Settings can change — every fur preset, custom
/// fur colours (with the colour that was picked beside the one that is drawn),
/// each accessory alone and with a hat in front, side and peeking poses, the
/// three sizes and both homes in the REAL island (idle, NEO's wake outline,
/// NEO's Allow / Cancel, the bars, mischief), and the Settings page itself.
/// Headless, like the other snapshot modes: no window, no Screen Recording.
@MainActor
enum PetCustomSnapshots {

    static let background = Color(.sRGB, red: 0.1, green: 0.1, blue: 0.11)
    static let desktop = Color(.sRGB, red: 0.42, green: 0.42, blue: 0.45)

    static func render(directory: String) -> Int32 {
        let geometry = NotchGeometry.detectMain()
        var sections: [CGImage] = []
        // Every section is `sheetWidth * 2` pixels wide: laid out narrower and
        // rendered at a higher scale where the detail is small.
        func add(_ title: String, scale: CGFloat = 2, @ViewBuilder _ content: () -> some View) {
            let view = VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13 * 2 / scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                content()
            }
            .padding(16 * 2 / scale)
            .frame(width: sheetWidth * 2 / scale, alignment: .leading)
            .background(background)
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            if let image = renderer.cgImage {
                sections.append(image)
            } else {
                print("\(title): render failed")
            }
        }

        add("Fur — the ten presets") { furPresets }
        add("Fur — a colour of your own: the pick (dot) and the fox drawn from it, kept readable on black") { customFurs }
        add("Accessories — each alone (front, NEO's poses, asleep, side, peeking) and with a hat") { accessories }
        add("Size and home — the real island at each size, on each side (hardware notch masked in black)", scale: 3) {
            islands(geometry: geometry)
        }
        add("Settings → Pet — as it opens, and customised") { settingsPages(geometry: geometry) }

        let width = sections.map(\.width).max() ?? 0
        let height = sections.map(\.height).reduce(0, +)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = height
        for image in sections {
            top -= image.height
            context.draw(image, in: CGRect(x: 0, y: top, width: image.width, height: image.height))
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("pet-custom.png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("\(width) x \(height) → \(file.path)")
        return 0
    }

    static let sheetWidth: CGFloat = 1180

    // MARK: - Tiles

    /// One frame of the fox on the island's black, enlarged, with a caption.
    static func tile(_ frame: String, palette: PetPalette = .fox, hat: PetHat? = nil, accessory: PetAccessory? = nil,
                     caption: String, pick: UInt32? = nil, scale: CGFloat = 4) -> some View {
        VStack(spacing: 4) {
            PetCanvas(frameName: frame, scale: scale, palette: palette, hat: hat, accessory: accessory)
                .padding(.top, CGFloat(PetCanvas.headroom) * scale)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black))
                .overlay(alignment: .topLeading) {
                    if let pick {
                        Circle().fill(PetCanvas.color(pick))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
                            .padding(5)
                    }
                }
            Text(caption)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    static var furPresets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(PetLook.allCases, id: \.self) { look in
                    tile("sit", palette: .look(look), caption: look.title)
                }
            }
            HStack(spacing: 10) {
                ForEach(PetLook.allCases, id: \.self) { look in
                    tile("run_1", palette: .look(look), caption: "running", scale: 2)
                    tile("sleep_1", palette: .look(look), caption: "asleep", scale: 2)
                }
            }
        }
    }

    static var customFurs: some View {
        let picks: [(String, PetFurColor)] = [
            ("violet (default)", .default),
            ("crimson", PetFurColor(hue: 0.97, saturation: 0.85, lightness: 0.5)),
            ("lime", PetFurColor(hue: 0.26, saturation: 0.8, lightness: 0.55)),
            ("ocean", PetFurColor(hue: 0.58, saturation: 0.9, lightness: 0.55)),
            ("gold", PetFurColor(hue: 0.13, saturation: 0.95, lightness: 0.55)),
            ("grey", PetFurColor(hue: 0, saturation: 0, lightness: 0.5)),
            ("black → lifted", PetFurColor(hue: 0.6, saturation: 0.3, lightness: 0.02)),
            ("navy → lifted", PetFurColor(hue: 0.66, saturation: 1, lightness: 0.2)),
            ("white → held down", PetFurColor(hue: 0.5, saturation: 0.2, lightness: 0.98)),
            ("yellow → held down", PetFurColor(hue: 0.16, saturation: 1, lightness: 0.7)),
        ]
        return HStack(spacing: 10) {
            ForEach(picks.indices, id: \.self) { index in
                let pick = picks[index].1
                tile("sit", palette: .custom(pick), caption: picks[index].0,
                     pick: PetColor.hsl(pick.hue, pick.saturation, pick.lightness))
            }
        }
    }

    static var accessories: some View {
        let poses: [(String, String, PetHat?)] = [
            ("sit", "sit", nil), ("alert", "listening", nil), ("code_think_1", "thinking", nil), ("code_alert", "needs OK", nil),
            ("happy", "speaking", nil), ("sleep_1", "asleep", nil), ("run_1", "pacing (side)", nil), ("sneak_1", "sniffing (side)", nil),
            ("peek_1" + PetFrame.mirrorSuffix, "peeking, left", nil), ("peek_1", "peeking", nil),
            ("sit", "+ party hat", .party), ("alert", "+ witch hat", .witch), ("run_1", "+ santa hat", .santa), ("happy", "+ bunny ears", .bunny),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(PetAccessory.allCases, id: \.self) { accessory in
                HStack(spacing: 8) {
                    Text(accessory.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(width: 74, alignment: .leading)
                    ForEach(poses.indices, id: \.self) { index in
                        tile(poses[index].0, hat: poses[index].2, accessory: accessory, caption: poses[index].1, scale: 3)
                    }
                }
            }
        }
    }

    // MARK: - The real island

    struct Cell {
        var caption: String
        var state: IslandState = .idle
        var size: PetSize = .normal
        var side: PetSide = .right
        var animation: PetAnimationID = .sit
        var elapsed: TimeInterval = 0
        /// The brain's dock reach (normal size's): full, a peek's, or closed.
        var reach: CGFloat = PetLayout.idleDock
        var hat: PetHat? = nil
        var accessory: PetAccessory? = nil
        var look: PetLook = .fox
        var glow: PetGlowColor = .blue
        /// Seconds NEO has been listening; `nil`: it is not.
        var listening: TimeInterval? = nil
        var activity: Activity? = nil
    }

    static let islandMargin: CGFloat = 88
    /// A browser in front, Wi-Fi on: wings narrow enough for a cell.
    static let wingsSample = WingStatus(left: WingItem(symbol: "safari", label: "Safari"), right: [WingItem(symbol: "wifi", label: "Wi-Fi")],
                                        musicPlaying: false, strip: nil)

    static func island(_ cell: Cell, geometry: NotchGeometry, margin: CGFloat? = nil) -> some View {
        let islandMargin = margin ?? Self.islandMargin
        let notch = geometry.notchFrame
        let regionMinX = notch.minX - islandMargin
        let regionWidth = notch.width + islandMargin * 2
        let metrics = PetMetrics(cell.size)
        let now = Date()
        var content: IslandContentSize
        switch cell.state {
        case .wings:
            let sides = IslandMetrics.wings(wingsSample, petSlot: metrics.barSlot)
            content = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: sides.trail)
            content.wingLead = sides.lead
        case .compact:
            content = IslandContentSize(compactLead: 40, compactTrail: 60 + metrics.barSlot, wingSide: 0)
        default:
            content = .default
        }
        if cell.state == .idle {
            content.petDock = metrics.dock(PetDock(side: cell.side, reach: cell.reach))
        } else if cell.state == .neoConfirm {
            content.petDock = PetDock(side: cell.side, reach: PetLayout.idleDock)
        }
        let frame = geometry.frame(for: cell.state, content: content)
        let local = CGRect(x: frame.minX - regionMinX, y: 0, width: frame.width, height: frame.height)
        let palette = PetPalette.look(cell.look)
        let pet = PetRenderModel(
            presentation: PetPresentation(mood: .idle, animation: cell.animation, startedAt: now.addingTimeInterval(-cell.elapsed - 0.001),
                                          mirrored: (cell.state == .idle || cell.state == .neoConfirm) && cell.side == .left),
            look: cell.look, hat: cell.hat, accessory: cell.accessory, size: cell.size, glow: cell.glow.rgb(palette: palette)
        )
        let panel: AnyView? = cell.state == .neoConfirm ? AnyView(NeoConfirmView(card: NeoConfirmSnapshots.card, hovered: nil)) : nil
        let height: CGFloat = cell.state == .neoConfirm ? frame.height + 6 : (cell.state == .expanded ? frame.height + 6 : 40)
        return VStack(alignment: .leading, spacing: 3) {
            IslandView(
                current: cell.activity, stackCount: 0, state: cell.state, localFrame: local, cornerRadius: 10,
                notchInset: notch.height, isIdle: cell.state == .idle, wingStatus: cell.state == .wings ? wingsSample : WingStatus(),
                notchWidth: notch.width, contentSize: content, panelContent: panel, surfaceVisible: true, pet: pet, hasNotch: true,
                listening: nil,
                neoListeningActive: cell.listening != nil
            )
            .frame(width: regionWidth, height: height)
            .background(desktop)
            .overlay(alignment: .topLeading) {
                NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: DesignTokens.radiusNotchTopFlare)
                    .fill(Color.black)
                    .frame(width: notch.width, height: notch.height)
                    .offset(x: notch.minX - regionMinX)
            }
            .clipped()
            Text(cell.caption)
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    static func islands(geometry: NotchGeometry) -> some View {
        let peak = NeoListeningLayout.pulseRise
        let song = NeoSnapshots.songSample
        var rows: [[Cell]] = []
        for size in PetSize.allCases {
            let name = "\(size.title) (\(Int(size.points)) pt)"
            rows.append([
                Cell(caption: "\(name) — home right", size: size),
                Cell(caption: "\(name) — home left", size: size, side: .left),
            ])
            rows.append([
                Cell(caption: "\(name) — scarf + witch hat, sakura", size: size, hat: .witch, accessory: .scarf, look: .sakura),
                Cell(caption: "\(name), left — headphones, midnight", size: size, side: .left, accessory: .headphones, look: .midnight),
            ])
        }
        for size in [PetSize.small, .large] {
            let name = size.title
            rows.append([
                Cell(caption: "\(name) — NEO listening, signal (teal)", size: size, animation: .neoListen, listening: peak),
                Cell(caption: "\(name), left — wake outline “match fur”, cyber", size: size, side: .left, animation: .neoListen,
                     accessory: .headphones, look: .cyber, glow: .matchFur, listening: peak),
            ])
            rows.append([
                Cell(caption: "\(name) — wake outline violet, sunglasses", size: size, animation: .neoListen,
                     accessory: .sunglasses, glow: .violet, listening: peak),
                Cell(caption: "\(name) — thinking, party hat + glasses", size: size, animation: .neoThink, hat: .party, accessory: .glasses),
            ])
            rows.append([
                Cell(caption: "\(name) — NEO needs an OK: Allow / Cancel", state: .neoConfirm, size: size, animation: .neoAsk, accessory: .glasses),
                Cell(caption: "\(name), left — NEO needs an OK", state: .neoConfirm, size: size, side: .left, animation: .neoAsk, accessory: .bowtie),
            ])
            rows.append([
                Cell(caption: "\(name) — hover wings", state: .wings, size: size, accessory: .scarf),
                Cell(caption: "\(name) — compact bar (a song)", state: .compact, size: size, animation: .music, accessory: .sunglasses, activity: song),
            ])
            rows.append([
                Cell(caption: "\(name) — peeking out of the notch", size: size, animation: .peek, elapsed: 1.0, reach: PetLayout.peekReach, accessory: .glasses),
                Cell(caption: "\(name), left — peeking", size: size, side: .left, animation: .peek, elapsed: 1.0, reach: PetLayout.peekReach, accessory: .headphones),
            ])
            rows.append([
                Cell(caption: "\(name) — dashing in under the notch", size: size, animation: .dashIn, elapsed: 0.36, accessory: .scarf),
                Cell(caption: "\(name) — hop at its peak, santa hat", size: size, animation: .hop, elapsed: 0.21, hat: .santa, accessory: .bowtie),
            ])
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows[row].indices, id: \.self) { index in
                        island(rows[row][index], geometry: geometry)
                    }
                }
            }
            let wide = (geometry.frame(for: .expanded, content: .default).width - geometry.notchFrame.width) / 2 + 6
            island(Cell(caption: "Small — expanded island (the pet 28 pt)", state: .expanded, size: .small, accessory: .scarf, activity: song),
                   geometry: geometry, margin: wide)
            island(Cell(caption: "Large — expanded island (the pet 40 pt)", state: .expanded, size: .large, hat: .party, accessory: .glasses, activity: song),
                   geometry: geometry, margin: wide)
        }
    }

    // MARK: - Settings

    static func settingsPages(geometry: NotchGeometry) -> some View {
        let width = geometry.frame(for: .settings, content: .default).width
        var custom = IslandSettings()
        custom.pet.usesCustomFur = true
        custom.pet.customFur = PetFurColor(hue: 0.58, saturation: 0.85, lightness: 0.6)
        custom.pet.glow = .matchFur
        custom.pet.hat = .party
        custom.pet.accessory = .glasses
        custom.pet.size = .large
        custom.pet.home = .left
        custom.pet.energy = .playful
        custom.pet.sleepsAtNight = true
        custom.pet.name = "Biscuit"
        return HStack(alignment: .top, spacing: 16) {
            ForEach([IslandSettings(), custom].indices, id: \.self) { index in
                SettingsView(settings: .constant(index == 0 ? IslandSettings() : custom), onChange: {}, page: .pet, scrolls: false)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black))
            }
        }
    }
}
