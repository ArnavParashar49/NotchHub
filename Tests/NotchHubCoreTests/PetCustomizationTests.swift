import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

/// Making the pet one's own: its colours, what it wears, its size and side of
/// the notch, its temperament, its night and its name — and that none of it
/// changes anything while every setting is at its default.
@Suite("Pet customisation")
struct PetCustomizationTests {

    let t0 = Date(timeIntervalSince1970: 3_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func roaming() -> PetContext {
        var c = PetContext()
        c.canRoam = true
        c.mischief = true
        return c
    }

    /// The 14-inch MacBook Pro this app runs on.
    let geometry = NotchGeometry.make(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    )

    /// The frames the fox itself is drawn in (not hats, not accessories).
    var petFrames: [String] {
        PetArt.frames.keys.filter { !$0.hasPrefix("hat_") && !$0.hasPrefix("acc_") }.sorted()
    }

    // MARK: - Settings

    @Test("every customisation survives a save and a load")
    func settingsRoundTrip() throws {
        var settings = PetSettings()
        settings.look = .midnight
        settings.usesCustomFur = true
        settings.customFur = PetFurColor(hue: 0.42, saturation: 0.7, lightness: 0.55)
        settings.glow = .matchFur
        settings.hat = .party
        settings.accessory = .scarf
        settings.size = .large
        settings.home = .left
        settings.energy = .playful
        settings.sleepsAtNight = true
        settings.nightStart = 23
        settings.nightEnd = 6
        settings.name = "Biscuit"
        let back = try JSONDecoder().decode(PetSettings.self, from: JSONEncoder().encode(settings))
        #expect(back == settings)
        #expect(back.night == PetNight(startHour: 23, endHour: 6))
        #expect(back.displayName == "Biscuit")
        // And the defaults are the defaults.
        let plain = try JSONDecoder().decode(PetSettings.self, from: JSONEncoder().encode(PetSettings()))
        #expect(plain == PetSettings())
    }

    @Test("settings saved by an older build decode with every new option at its default")
    func settingsBackwardCompatible() throws {
        // Exactly what the build before customisation wrote.
        let old = #"{"showPet":true,"reactions":false,"idleAnimations":true,"interaction":true,"mischief":false,"look":"silver","hat":"witch","holidays":false}"#
        let settings = try JSONDecoder().decode(PetSettings.self, from: Data(old.utf8))
        #expect(settings.reactions == false && settings.mischief == false && settings.holidays == false)
        #expect(settings.look == .silver && settings.hat == .witch)
        let defaults = PetSettings()
        #expect(settings.usesCustomFur == false && settings.customFur == defaults.customFur)
        #expect(settings.glow == .blue && settings.glowColor == nil)
        #expect(settings.accessory == .none && settings.accessory.accessory == nil)
        #expect(settings.size == .normal && settings.home == .right && settings.energy == .normal)
        #expect(settings.sleepsAtNight == false && settings.night == nil)
        #expect(settings.name == "Neo" && settings.displayName == PetIdentity.name)
        #expect(settings.palette == .look(.silver))
        // Nothing at all saved: the pet as it always was.
        #expect(try JSONDecoder().decode(PetSettings.self, from: Data("{}".utf8)) == defaults)
        #expect(defaults.palette == .fox && defaults.palette.map.isEmpty)
    }

    @Test("values a newer build saved, or of the wrong type, fall back one by one")
    func settingsUnknownValues() throws {
        let future = """
        {"showPet":false,"look":"galaxy","hat":"crown","glow":"plasma","accessory":"cape","size":"huge","home":"top",
         "energy":"hyper","usesCustomFur":"yes","customFur":"#ff00ff","sleepsAtNight":1,"nightStart":99,"nightEnd":-4,
         "name":"   A very long name indeed, far too long   ","somethingNew":{"a":1}}
        """
        let settings = try JSONDecoder().decode(PetSettings.self, from: Data(future.utf8))
        let defaults = PetSettings()
        #expect(settings.showPet == false)
        #expect(settings.look == .fox && settings.hat == .seasonal)
        #expect(settings.glow == .blue && settings.accessory == .none)
        #expect(settings.size == .normal && settings.home == .right && settings.energy == .normal)
        #expect(settings.usesCustomFur == false && settings.customFur == defaults.customFur)
        #expect(settings.sleepsAtNight == false)
        #expect(settings.nightStart == 23 && settings.nightEnd == 0)
        #expect(settings.name == "A very long name")
        // A known value beside an unknown one is kept.
        let mixed = #"{"size":"small","home":"sideways","energy":"calm","customFur":{"hue":7,"saturation":-1,"lightness":0.5}}"#
        let kept = try JSONDecoder().decode(PetSettings.self, from: Data(mixed.utf8))
        #expect(kept.size == .small && kept.home == .right && kept.energy == .calm)
        #expect(kept.customFur == PetFurColor(hue: 1, saturation: 0, lightness: 0.5))
    }

    @Test("a name is trimmed, kept to 16 characters on one line, and never empty")
    func names() {
        #expect(PetIdentity.validName("Neo") == "Neo")
        #expect(PetIdentity.validName("  Biscuit \n") == "Biscuit")
        #expect(PetIdentity.validName("") == "Neo")
        #expect(PetIdentity.validName("   \t\n ") == "Neo")
        #expect(PetIdentity.validName("Sir Reginald Foxworth III") == "Sir Reginald Fox")
        #expect(PetIdentity.validName("Sir Reginald Foxworth III").count <= PetIdentity.maxNameLength)
        #expect(PetIdentity.validName("abcdefghijklmno pqrs") == "abcdefghijklmno") // no trailing space after the cut
        #expect(PetIdentity.validName("Mr\nFox") == "Mr Fox")
        #expect(PetIdentity.validName("狐狐狐狐狐狐狐狐狐狐狐狐狐狐狐狐狐狐").count == 16)
        #expect(PetIdentity.validName("X") == "X")
        #expect(PetIdentity.hello(name: "Biscuit") == "Hi, I'm Biscuit!")
        #expect(PetIdentity.hello == PetIdentity.hello(name: "Neo"))
        var settings = PetSettings()
        settings.name = "  Mochi  "
        #expect(settings.displayName == "Mochi" && settings.normalized.name == "Mochi")
        settings.name = ""
        #expect(settings.displayName == "Neo")
        // NEO the assistant keeps its own name whatever the pet is called.
        #expect(NeoListeningIndicator.accessibilityLabel == "Neo is listening")
    }

    // MARK: - Colours

    @Test("every preset look reads on black: fur against the island and the eyes, cream apart from the fur")
    func presetLooksAreLegible() {
        #expect(PetLook.allCases.count >= 10)
        for look in PetLook.allCases {
            let palette = PetPalette.look(look)
            #expect(palette.fur == look.swatch)
            #expect(PetColor.contrast(palette.fur, PetColor.black) >= 3, "\(look): fur on black")
            #expect(PetColor.contrast(palette.fur, palette.eyes) >= 3, "\(look): eyes on the fur")
            #expect(PetColor.contrast(palette.fur, palette.outline) >= 2.5, "\(look): outline on the fur")
            #expect(PetColor.contrast(palette.cream, PetColor.black) >= 7, "\(look): cream on black")
            #expect(PetColor.contrast(palette.cream, palette.eyes) >= 7, "\(look): nose and eyes on the cream")
            let fur = PetColor.components(palette.fur), cream = PetColor.components(palette.cream)
            let apart = max(abs(fur.r - cream.r), abs(fur.g - cream.g), abs(fur.b - cream.b))
            #expect(apart >= 0.12, "\(look): cream \(apart) from the fur")
            #expect(PetColor.luminance(palette.shade) < PetColor.luminance(palette.fur), "\(look): the shade is darker")
            #expect(PetColor.luminance(palette.highlight) >= PetColor.luminance(palette.fur), "\(look): the highlight is lighter")
            // The palette is the look, colour for colour.
            for (_, rgb) in PetArt.palette {
                #expect(palette.color(rgb) == look.color(rgb))
            }
        }
        #expect(Set(PetLook.allCases.map(\.swatch)).count == PetLook.allCases.count) // ten different furs
    }

    @Test("any custom fur colour is drawn within legible bounds: never too dark for black, never too light for the cream")
    func customFurIsLegible() {
        var checked = 0
        for hueStep in 0..<36 {
            for saturation in stride(from: 0.0, through: 1.0, by: 0.125) {
                for lightness in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let pick = PetFurColor(hue: Double(hueStep) / 36, saturation: saturation, lightness: lightness)
                    let palette = PetPalette.custom(pick)
                    let label = "h\(hueStep) s\(saturation) l\(lightness)"
                    let luminance = PetColor.luminance(palette.fur)
                    // Byte rounding moves a luminance by a hair.
                    #expect(luminance >= PetPalette.furLuminance.lowerBound - 0.01, "\(label): fur luminance \(luminance)")
                    #expect(luminance <= PetPalette.furLuminance.upperBound + 0.01, "\(label): fur luminance \(luminance)")
                    #expect(PetColor.contrast(palette.fur, PetColor.black) >= 4, "\(label): fur on black")
                    #expect(PetColor.contrast(palette.fur, palette.outline) >= 3, "\(label): outline on the fur")
                    #expect(PetColor.contrast(palette.fur, palette.eyes) >= 3, "\(label): eyes on the fur")
                    #expect(PetColor.contrast(palette.cream, palette.fur) >= 1.4, "\(label): cream on the fur")
                    #expect(PetColor.luminance(palette.shade) < luminance, "\(label): the shade is darker")
                    #expect(PetColor.luminance(palette.highlight) > luminance, "\(label): the highlight is lighter")
                    #expect(PetColor.contrast(palette.shade, PetColor.black) >= 1.8, "\(label): the shade still shows on black")
                    #expect(PetColor.luminance(palette.outline) < 0.03, "\(label): the outline is nearly black")
                    // Only the fox's fur and outline change: cream, eyes, props and effects are the art's.
                    #expect(Set(palette.map.keys) == [PetPalette.baseFur, PetPalette.baseShade, PetPalette.baseHighlight, PetPalette.baseOutline])
                    checked += 1
                }
            }
        }
        #expect(checked == 36 * 9 * 21)
        // A pick that is already readable is drawn exactly as picked.
        let fine = PetFurColor(hue: 0.07, saturation: 0.8, lightness: 0.55)
        #expect(PetPalette.custom(fine).fur == PetColor.hsl(0.07, 0.8, 0.55))
        // Black is lifted, white is held down; both keep their hue.
        #expect(PetColor.luminance(PetPalette.custom(PetFurColor(hue: 0.6, saturation: 0.5, lightness: 0)).fur) >= 0.15)
        #expect(PetColor.luminance(PetPalette.custom(PetFurColor(hue: 0.6, saturation: 0.5, lightness: 1)).fur) <= 0.61)
        // Deriving is deterministic: the same pick, the same palette (so it can be cached on change).
        #expect(PetPalette.custom(fine) == PetPalette.custom(fine))
        var settings = PetSettings()
        settings.usesCustomFur = true
        settings.customFur = fine
        #expect(settings.palette == PetPalette.custom(fine))
        settings.usesCustomFur = false
        settings.look = .cocoa
        #expect(settings.palette == PetPalette.look(.cocoa))
    }

    @Test("colour arithmetic: luminance, contrast and HSL are the standard ones")
    func colourMath() {
        #expect(PetColor.luminance(0x000000) == 0)
        #expect(abs(PetColor.luminance(0xFFFFFF) - 1) < 1e-9)
        #expect(abs(PetColor.contrast(0xFFFFFF, 0x000000) - 21) < 1e-6)
        #expect(PetColor.contrast(0x123456, 0x123456) == 1)
        #expect(PetColor.hsl(0, 1, 0.5) == 0xFF0000)
        #expect(PetColor.hsl(1.0 / 3, 1, 0.5) == 0x00FF00)
        #expect(PetColor.hsl(2.0 / 3, 1, 0.5) == 0x0000FF)
        #expect(PetColor.hsl(0.3, 0, 0.5) == 0x808080)
        #expect(PetColor.hsl(1, 1, 0.5) == PetColor.hsl(0, 1, 0.5)) // the hue wraps
        #expect(PetColor.hsl(0.4, 0.7, 0) == 0x000000 && PetColor.hsl(0.4, 0.7, 1) == 0xFFFFFF)
    }

    @Test("the listening glow: blue is the design token's, the presets are bright, and “match fur” follows the fur")
    func glowColours() {
        #expect(PetGlowColor.blue.rgb(palette: .fox) == nil)
        for glow in PetGlowColor.allCases where glow != .blue {
            for look in PetLook.allCases {
                let rgb = glow.rgb(palette: .look(look))
                #expect(rgb != nil)
                #expect(PetColor.luminance(rgb ?? 0) >= 0.3, "\(glow) on \(look) is too dim to be a glow")
            }
        }
        #expect(PetGlowColor.matchFur.rgb(palette: .fox) == PetPalette.fox.highlight)
        #expect(PetGlowColor.matchFur.rgb(palette: .look(.cyber)) == PetPalette.look(.cyber).highlight)
        #expect(PetGlowColor.matchFur.rgb(palette: .look(.midnight)) != PetGlowColor.matchFur.rgb(palette: .look(.red)))
        var settings = PetSettings()
        #expect(settings.glowColor == nil)
        settings.glow = .violet
        #expect(settings.glowColor == 0xB18CFF)
    }

    // MARK: - Accessories

    @Test("every accessory has its front and side art, and every pet frame says how it wears them")
    func accessoryArt() {
        for accessory in PetAccessory.allCases {
            #expect(PetFrame.named(accessory.frameName) != nil, "missing \(accessory.frameName)")
            #expect(PetFrame.named(accessory.sideFrameName) != nil, "missing \(accessory.sideFrameName)")
            #expect(PetAccessoryChoice(rawValue: accessory.rawValue)?.accessory == accessory)
        }
        #expect(PetAccessoryChoice.none.accessory == nil)
        #expect(PetAccessoryChoice.allCases.count == PetAccessory.allCases.count + 1)
        for name in petFrames {
            let anchor = PetFrame.wearAnchor(for: name)
            if name.hasPrefix("tail_peek") {
                #expect(anchor == nil, "\(name) has no head to dress")
            } else {
                #expect(anchor != nil, "\(name) does not say how it wears accessories")
            }
        }
        for name in PetArt.wearAnchors.keys {
            #expect(petFrames.contains(name), "wear anchor for unknown frame \(name)")
        }
    }

    @Test("an accessory never draws outside the pet's frame, on any frame, facing either way")
    func accessoriesStayInTheFrame() {
        var drawn = 0
        for accessory in PetAccessory.allCases {
            for base in petFrames {
                for name in [base, base + PetFrame.mirrorSuffix] {
                    for run in PetFrame.accessoryRuns(accessory, on: name) {
                        #expect(run.length > 0)
                        #expect(run.x >= 0 && run.x + run.length <= PetFrame.size, "\(accessory) on \(name): x \(run.x)+\(run.length)")
                        #expect(run.y >= 0 && run.y < PetFrame.size, "\(accessory) on \(name): row \(run.y)")
                        drawn += 1
                    }
                }
                // Mirrored, it is the mirror image.
                let plain = PetFrame.accessoryRuns(accessory, on: base)
                let mirrored = PetFrame.accessoryRuns(accessory, on: base + PetFrame.mirrorSuffix)
                #expect(mirrored == plain.map { PetFrame.Run(x: PetFrame.size - $0.x - $0.length, y: $0.y, length: $0.length, color: $0.color) })
            }
        }
        #expect(drawn > 1000)
    }

    @Test("accessories are anchored to the head like hats: on the face, at the neck, over the ears — on every frame")
    func accessoriesFollowTheHead() {
        for name in petFrames {
            guard let wear = PetFrame.wearAnchor(for: name) else { continue }
            // The wear anchor is the hat anchor, or one row under it where the
            // frame already has something on its head.
            if let hat = PetFrame.hatAnchor(for: name), wear.view != .peek {
                #expect(wear.x == hat.x, "\(name): wear x \(wear.x), hat x \(hat.x)")
                #expect(wear.y == hat.y || wear.y == hat.y + 1, "\(name): wear y \(wear.y), hat y \(hat.y)")
            }
            for accessory in PetAccessory.allCases {
                let runs = PetFrame.accessoryRuns(accessory, on: name)
                if wear.hidden.contains(accessory.slot) {
                    #expect(runs.isEmpty, "\(accessory) on \(name) should be hidden by the prop")
                    continue
                }
                #expect(!runs.isEmpty, "\(accessory) is not drawn on \(name)")
                let rows = runs.map(\.y)
                let columns = runs.flatMap { [$0.x, $0.x + $0.length - 1] }
                // Rows from the top of the head: the face 1–6, the ears −1–5, the neck 4–9.
                let rowRange: ClosedRange<Int>
                switch accessory.slot {
                case .face: rowRange = (wear.y + 1)...(wear.y + 6)
                case .ears: rowRange = (wear.y - 1)...(wear.y + 5)
                case .neck: rowRange = (wear.y + 3)...(wear.y + 9)
                }
                #expect(rows.allSatisfy { rowRange.contains($0) || $0 == 0 || $0 == 15 }, "\(accessory) on \(name): rows \(rows) outside \(rowRange)")
                // Columns: within the head's reach of its middle (a scarf's end flies further back).
                let reach = accessory == .scarf ? 8 : 7
                #expect(columns.allSatisfy { abs($0 - wear.x) <= reach }, "\(accessory) on \(name): columns \(columns) far from x \(wear.x)")
            }
        }
        // It moves with the head: the same art, shifted by the anchor.
        let sit = PetFrame.accessoryRuns(.glasses, on: "sit")
        let alert = PetFrame.accessoryRuns(.glasses, on: "alert") // ears up: the head one row higher
        #expect(alert == sit.map { PetFrame.Run(x: $0.x, y: $0.y - 1, length: $0.length, color: $0.color) })
        let lean = PetFrame.accessoryRuns(.bowtie, on: "lean_right")
        #expect(lean == PetFrame.accessoryRuns(.bowtie, on: "sit").map { PetFrame.Run(x: $0.x + 1, y: $0.y, length: $0.length, color: $0.color) })
        // The fox's own headphones (its music frames) are the accessory's pixels: worn twice, they coincide.
        let own = PetFrame.named("headphones_on")!.runs
        for run in PetFrame.accessoryRuns(.headphones, on: "headphones_on") {
            for x in run.x..<(run.x + run.length) {
                #expect(own.contains { $0.y == run.y && $0.x <= x && x < $0.x + $0.length && $0.color == run.color },
                        "headphones pixel (\(x),\(run.y)) is not where the fox's own are")
            }
        }
    }

    @Test("every pose — NEO's, mischief, reactions — wears the accessory, and it stays inside a 32-pt strip at every size")
    func accessoriesInEveryAnimation() {
        let neo: [PetAnimationID] = [.neoWake, .neoListen, .neoThink, .neoPace, .neoSniff, .neoTalk, .neoAsk]
        for id in neo {
            for frame in id.animation.frames {
                for accessory in PetAccessory.allCases {
                    #expect(!PetFrame.accessoryRuns(accessory, on: frame).isEmpty, "\(id) frame \(frame) loses its \(accessory)")
                }
            }
        }
        let notch: CGFloat = 32
        for size in PetSize.allCases {
            let metrics = PetMetrics(size)
            let top = metrics.stripY(notchHeight: notch)
            for id in PetAnimationID.allCases {
                let animation = id.animation
                for index in animation.frames.indices {
                    let lift = PetMetrics.points(animation.offset(forFrame: index).dy, scale: metrics.scale)
                    for accessory in PetAccessory.allCases {
                        for run in PetFrame.accessoryRuns(accessory, on: animation.frames[index]) {
                            let minY = top + lift + CGFloat(run.y) * metrics.scale
                            let maxY = top + lift + CGFloat(run.y + 1) * metrics.scale
                            #expect(minY >= 0 && maxY <= notch, "\(size) \(id) frame \(index): \(accessory) at \(minY)…\(maxY)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Size

    @Test("the three sizes: 14, 16 and 20 pt, and the normal one is exactly the pet as it was")
    func sizes() {
        #expect(PetSize.allCases.map(\.points) == [14, 16, 20])
        let normal = PetMetrics(.normal)
        #expect(normal.side == PetLayout.artSize && normal.scale == 1)
        #expect(normal.dockInset == PetLayout.dockInset)
        #expect(normal.barSlot == PetLayout.barSlot)
        #expect(normal.idleDock == PetLayout.idleDock)
        #expect(normal.peekReach == PetLayout.peekReach)
        #expect(normal.expandedScale == PetLayout.expandedScale)
        #expect(normal.expandedReserve == PetLayout.expandedReserve)
        #expect(normal.stripY(notchHeight: 32) == 8)
        for height in stride(from: CGFloat(22), through: 44, by: 1) {
            #expect(normal.stripY(notchHeight: height) == ((height - 16) / 2).rounded(.down)) // as it always was, on any notch
        }
        let small = PetMetrics(.small), large = PetMetrics(.large)
        #expect(small.scale == 0.875 && large.scale == 1.25)
        #expect(small.dockInset == 8 && large.dockInset == 11)
        #expect(small.idleDock == 30 && large.idleDock == 42)
        #expect(small.peekReach == 11 && large.peekReach == 14)
        #expect(small.barSlot == 20 && large.barSlot == 26)
        #expect(small.expandedScale == 1.75 && large.expandedScale == 2.5)
        #expect(small.expandedReserve == 42 && large.expandedReserve == 54)
        // Every measurement is a whole number of points.
        for metrics in [small, normal, large] {
            for value in [metrics.side, metrics.dockInset, metrics.idleDock, metrics.peekReach, metrics.barSlot,
                          metrics.expandedReserve, metrics.stripY(notchHeight: 32), PetLayout.artSize * metrics.expandedScale] {
                #expect(value == value.rounded(), "\(metrics.size): \(value)")
            }
        }
        // A brain's dock, as each size draws it.
        for metrics in [small, normal, large] {
            for side in [PetSide.left, .right] {
                #expect(metrics.dock(PetDock(side: side, reach: PetLayout.idleDock)) == PetDock(side: side, reach: metrics.idleDock))
                #expect(metrics.dock(PetDock(side: side, reach: PetLayout.peekReach)) == PetDock(side: side, reach: metrics.peekReach))
                #expect(metrics.dock(PetDock(side: side, reach: 0)) == PetDock(side: side, reach: 0))
            }
            let half = metrics.dock(PetDock(side: .right, reach: 17)).reach
            #expect(half > 0 && half < metrics.idleDock && half == half.rounded())
        }
        #expect(normal.dock(PetDock(side: .left, reach: 21.5)) == PetDock(side: .left, reach: 21.5)) // normal: untouched
    }

    @Test("nearest-neighbour pixels: at every size each art pixel lands on device pixels, in order, none lost")
    func crispPixels() {
        for size in PetSize.allCases {
            for scale in [PetMetrics(size).scale, PetMetrics(size).expandedScale] {
                for grid in [CGFloat(1), 2, 3] {
                    var previous = PetMetrics.pixelEdge(-8, scale: scale, grid: grid)
                    #expect(previous == -8 * scale) // the frame's own edges are whole points
                    for pixel in -7...16 {
                        let edge = PetMetrics.pixelEdge(CGFloat(pixel), scale: scale, grid: grid)
                        #expect((edge * grid).rounded() == edge * grid, "\(size) ×\(grid): edge \(edge) is between device pixels")
                        if scale * grid >= 1 {
                            #expect(edge > previous, "\(size) ×\(grid): pixel \(pixel - 1) vanished")
                        }
                        // Never more than half a device pixel from where it would be exactly.
                        #expect(abs(edge - CGFloat(pixel) * scale) <= 0.5 / grid + 1e-9)
                        previous = edge
                    }
                    #expect(PetMetrics.pixelEdge(16, scale: scale, grid: grid) == 16 * scale)
                }
            }
            // A whole scale is untouched by the grid.
            #expect(PetMetrics.pixelEdge(5, scale: 2, grid: 2) == 10)
            // Offsets are whole points at every size, and the art's own at the normal one.
            for pixels in -30...30 {
                let points = PetMetrics.points(pixels, scale: PetMetrics(size).scale)
                #expect(points == points.rounded())
                #expect(PetMetrics.points(pixels, scale: 1) == CGFloat(pixels))
                #expect(PetMetrics.points(pixels, scale: 2) == CGFloat(pixels) * 2)
            }
        }
    }

    @Test("every island shape places the pet at its chosen size, inside the island; the normal size is unchanged")
    func sizeInEveryShape() {
        let notch = geometry.notchFrame
        let strip: [IslandState] = [.idle, .wings, .compact, .interactive, .appPanel, .meeting, .neoConfirm]
        for size in PetSize.allCases {
            let metrics = PetMetrics(size)
            for side in [PetSide.right, .left] {
                var content = IslandContentSize.default
                content.wingSide = 96 + metrics.barSlot
                content.compactTrail = 70 + metrics.barSlot
                for state in IslandState.allCases {
                    let dock = metrics.dock(PetDock(side: side, reach: PetLayout.idleDock))
                    content.petDock = state == .idle ? dock : nil
                    let frame = geometry.frame(for: state, content: content)
                    let placed = PetLayout.placement(for: state, islandSize: frame.size, notchHeight: notch.height, dock: dock, size: size)
                    if size == .normal {
                        // Exactly the placement the app has always had.
                        #expect(placed == PetLayout.placement(for: state, islandSize: frame.size, notchHeight: notch.height, dock: dock))
                    }
                    guard let pet = placed else {
                        #expect(!NeoListeningLayout.shows(in: state), "\(state) lost its pet")
                        continue
                    }
                    let label = "\(size) \(side) \(state)"
                    #expect(pet.size == (state == .expanded ? metrics.side * 2 : metrics.side), "\(label): size \(pet.size)")
                    // Whole points from the edge it rides (and from the top), so its pixels sit on the grid.
                    let fromEdge = pet.anchor == .leading ? pet.origin.x : frame.width - pet.origin.x
                    #expect(fromEdge == fromEdge.rounded() && pet.origin.y == pet.origin.y.rounded(), "\(label): off the point grid")
                    #expect(pet.origin.x >= 0 && pet.origin.x + pet.size <= frame.width, "\(label): x \(pet.origin.x) in \(frame.width)")
                    #expect(pet.origin.y >= 0 && pet.origin.y + pet.size <= frame.height, "\(label): y \(pet.origin.y)")
                    if strip.contains(state) {
                        #expect(pet.origin.y + pet.size <= notch.height - 2, "\(label): on the strip's bottom edge")
                        // Beside the notch, never behind it.
                        let minX = frame.minX + pet.origin.x
                        #expect(minX >= notch.maxX || minX + pet.size <= notch.minX, "\(label): behind the notch")
                        // NEO's glow at the peak of its pulse stays inside the strip's height.
                        let glow = NeoListeningLayout.glowFrame(behind: pet, scale: NeoListeningLayout.pulseScaleRange.upperBound)
                        #expect(glow.minY >= 0 && glow.maxY <= notch.height, "\(label): glow \(glow.minY)…\(glow.maxY)")
                    }
                }
                // On its dock: inset from the notch's edge on its side, and the dock holds the pet and its glow.
                let dock = metrics.dock(PetDock(side: side, reach: PetLayout.idleDock))
                content.petDock = dock
                let idle = geometry.frame(for: .idle, content: content)
                #expect(idle.width == notch.width + metrics.idleDock)
                let pet = PetLayout.placement(for: .idle, islandSize: idle.size, notchHeight: notch.height, dock: dock, size: size)!
                let minX = idle.minX + pet.origin.x
                if side == .right {
                    #expect(minX == notch.maxX + metrics.dockInset)
                    #expect(idle.maxX - (minX + pet.size) == metrics.dockInset)
                } else {
                    #expect(minX + pet.size == notch.minX - metrics.dockInset)
                    #expect(minX - idle.minX == metrics.dockInset)
                }
                let glow = NeoListeningLayout.glowFrame(behind: pet)
                #expect(glow.minX >= 0 && glow.maxX <= idle.width, "\(size) \(side): the glow leaves the dock")
            }
            // The bars keep exactly the pet's room: the reserve is the pet and its gap.
            #expect(metrics.barSlot == metrics.side + PetLayout.gap)
            let expanded = geometry.frame(for: .expanded, content: .default)
            let big = PetLayout.placement(for: .expanded, islandSize: expanded.size, notchHeight: 32, size: size)!
            #expect(expanded.width - big.origin.x <= metrics.expandedReserve + DesignTokens.contentInset)
            let reserved = MediaControlLayout.placement(in: expanded, notchInset: 32, trailingReserve: metrics.expandedReserve)
            #expect(reserved.cluster.maxX <= expanded.minX + big.origin.x, "\(size): the transport runs under the pet")
        }
    }

    @Test("mischief at every size: hidden is wholly under the notch, and a peek shows exactly its eight columns")
    func mischiefGeometryScales() {
        for size in PetSize.allCases {
            let metrics = PetMetrics(size)
            // From the notch's edge: the pet stands `dockInset` out.
            let hidden = metrics.dockInset + PetMetrics.points(PetLayout.hiddenOffset, scale: metrics.scale)
            #expect(hidden + metrics.side <= 0, "\(size): hidden pet shows \(hidden + metrics.side) pt")
            let peek = metrics.dockInset + PetMetrics.points(PetLayout.peekOffset, scale: metrics.scale)
            #expect(peek + 8 * metrics.scale == 0, "\(size): the peek's column 8 is \(peek + 8 * metrics.scale) pt from the notch's edge")
            #expect(peek + metrics.side <= metrics.peekReach, "\(size): the peek outgrows its dock")
            #expect(metrics.peekReach < metrics.idleDock)
        }
    }

    @Test("NEO's Allow / Cancel: at every size and on either side the fox keeps its place, inside the surface")
    func confirmAtEverySize() {
        let notch = geometry.notchFrame
        let confirm = geometry.frame(for: .neoConfirm, content: .default)
        #expect(confirm.width == notch.width + PetLayout.idleDock * 2) // the surface itself never changes
        for size in PetSize.allCases {
            let metrics = PetMetrics(size)
            for side in [PetSide.right, .left] {
                let dock = metrics.dock(PetDock(side: side, reach: PetLayout.idleDock))
                var content = IslandContentSize.default
                content.petDock = dock
                let idle = geometry.frame(for: .idle, content: content)
                let atRest = PetLayout.placement(for: .idle, islandSize: idle.size, notchHeight: notch.height, dock: dock, size: size)!
                let asking = PetLayout.placement(for: .neoConfirm, islandSize: confirm.size, notchHeight: notch.height, dock: dock, size: size)!
                #expect(idle.minX + atRest.origin.x == confirm.minX + asking.origin.x, "\(size) \(side): the fox moved")
                #expect(atRest.origin.y == asking.origin.y && atRest.scale == asking.scale && atRest.anchor == asking.anchor)
                #expect(asking.origin.x >= 0 && asking.origin.x + asking.size <= confirm.width, "\(size) \(side): outside the surface")
                // Above the buttons, clear of them.
                let buttons = NeoConfirmLayout.buttons(in: confirm, notchInset: notch.height)
                let petBottom = confirm.maxY - asking.origin.y - asking.size
                #expect(buttons.allSatisfy { $0.rect.maxY < petBottom }, "\(size) \(side): over the buttons")
            }
        }
    }

    // MARK: - Home

    /// One step of a brain, as the island sees it.
    struct Seen: Equatable {
        var side: PetSide
        var reach: CGFloat
        var animation: PetAnimationID
        var mood: PetMood
        var mirrored: Bool
    }

    func trace(_ brain: inout PetBrain, _ context: PetContext, until end: TimeInterval) -> [(TimeInterval, Seen)] {
        var t: TimeInterval = 0
        var seen: [(TimeInterval, Seen)] = []
        func note(_ b: PetBrain) {
            seen.append((t, Seen(side: b.dock.side, reach: b.dock.reach, animation: b.presentation.animation,
                                 mood: b.presentation.mood, mirrored: b.presentation.mirrored)))
        }
        brain.update(context, now: at(t))
        note(brain)
        while t < end, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
            note(brain)
        }
        return seen
    }

    @Test("home on the right is the pet as it always was — choosing it changes nothing")
    func homeRightIsTheDefault() {
        for seed in [UInt64(1), 7, 42, 0x5EED_F0C5] {
            var plain = PetBrain(now: t0, seed: seed)
            var chosen = PetBrain(now: t0, seed: seed)
            chosen.setHome(.right, now: t0)
            #expect(plain.home == .right && plain.homeSide == .right && plain.dock == .home && plain.homeDock == .home)
            let a = trace(&plain, roaming(), until: 170)
            let b = trace(&chosen, roaming(), until: 170)
            #expect(a.map(\.0) == b.map(\.0))
            #expect(a.map(\.1) == b.map(\.1))
            #expect(a.contains { $0.1.mood == .mischief }, "seed \(seed) never played")
        }
    }

    @Test("home on the left is the same life mirrored: same beats, same moments, the other side of the notch")
    func homeLeftMirrors() {
        for seed in [UInt64(1), 7, 42, 99] {
            var right = PetBrain(now: t0, seed: seed)
            var left = PetBrain(now: t0, seed: seed)
            left.setHome(.left, now: t0)
            #expect(left.home == .left && left.homeSide == .left)
            #expect(left.dock == PetDock(side: .left, reach: PetLayout.idleDock))
            #expect(left.presentation.mirrored)
            let a = trace(&right, roaming(), until: 170)
            let b = trace(&left, roaming(), until: 170)
            #expect(a.map(\.0) == b.map(\.0), "seed \(seed): the two lives keep different time")
            for (x, y) in zip(a, b) {
                #expect(y.1 == Seen(side: x.1.side.opposite, reach: x.1.reach, animation: x.1.animation, mood: x.1.mood, mirrored: !x.1.mirrored),
                        "seed \(seed) at \(x.0)s")
            }
            // Its games really took it to the other side, and brought it back.
            #expect(b.contains { $0.1.side == .right && $0.1.reach == PetLayout.idleDock })
            #expect(b.contains { $0.1.mood == .mischief })
        }
    }

    @Test("from a home on the left: a crossing visits the right, anything that needs the pet sends it home to the left")
    func homeLeftComesHome() {
        var brain = PetBrain(now: t0, seed: 3)
        brain.setHome(.left, now: t0)
        var context = roaming()
        brain.update(context, now: t0)
        brain.startMischief(.crossOver, now: at(1))
        var t: TimeInterval = 1
        while brain.mischief != nil, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
        }
        #expect(brain.dock == PetDock(side: .right, reach: PetLayout.idleDock)) // visiting
        #expect(!brain.presentation.mirrored)
        // Mischief goes off: the quick way home, to the LEFT.
        context.mischief = false
        brain.update(context, now: at(t + 0.5))
        #expect(brain.mischief == .returnHome)
        t += 0.5
        while brain.mischief != nil, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
        }
        #expect(brain.dock == PetDock(side: .left, reach: PetLayout.idleDock))
        #expect(brain.presentation.mirrored)
        // Leaving the resting dock mid-game drops it at home — the left.
        context.mischief = true
        brain.startMischief(.hideAndSeek, now: at(t + 1))
        brain.update(context, now: at(t + 1.2))
        #expect(brain.mischief != nil)
        context.canRoam = false
        brain.update(context, now: at(t + 1.3))
        #expect(brain.mischief == nil && brain.dock == brain.homeDock && brain.dock.side == .left)
    }

    @Test("changing home moves the pet there at once, and drops a game in progress")
    func changingHome() {
        var brain = PetBrain(now: t0, seed: 5)
        let context = roaming()
        brain.update(context, now: t0)
        brain.startMischief(.zoomies, now: at(1))
        brain.update(context, now: at(1.1))
        brain.setHome(.left, now: at(1.2))
        #expect(brain.mischief == nil)
        #expect(brain.dock == PetDock(side: .left, reach: PetLayout.idleDock) && brain.presentation.mirrored)
        brain.setHome(.right, now: at(2))
        #expect(brain.dock == .home && !brain.presentation.mirrored)
        // Auto adopts the side it is on, without moving.
        brain.setHome(.left, now: at(3))
        brain.setHome(.auto, now: at(4))
        #expect(brain.home == .auto && brain.homeSide == .left && brain.dock.side == .left)
        brain.setHome(.auto, now: at(5)) // again: nothing
        #expect(brain.homeSide == .left)
    }

    @Test("auto: no fixed home — the pet stays on whichever side a game leaves it")
    func autoHomeStays() {
        var brain = PetBrain(now: t0, seed: 11)
        brain.setHome(.auto, now: t0)
        #expect(brain.homeSide == .right) // it starts where it always lived
        let context = roaming()
        brain.update(context, now: t0)
        brain.startMischief(.crossOver, now: at(1))
        var t: TimeInterval = 1
        while brain.mischief != nil, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
        }
        #expect(brain.dock == PetDock(side: .left, reach: PetLayout.idleDock))
        #expect(brain.homeSide == .left && brain.homeDock == brain.dock) // home is here now
        // Something needs the pet: with a fixed home it would run back. Here it stays.
        var quiet = context
        quiet.mischief = false
        brain.update(quiet, now: at(t + 1))
        #expect(brain.mischief == nil && brain.dock.side == .left)
        // And over the rest of its waking life it never plays "return home".
        var sides: Set<PetSide> = []
        var kinds: Set<PetMischief> = []
        while t < 175, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
            if let kind = brain.mischief { kinds.insert(kind) }
            if brain.mischief == nil { sides.insert(brain.dock.side) }
            #expect(brain.mischief == nil ? brain.dock.side == brain.homeSide : true)
        }
        #expect(!kinds.contains(.returnHome))
    }

    // MARK: - Energy

    /// How many games and flourishes a pet gets through in its first `seconds`, over many seeds.
    func liveliness(_ energy: PetEnergy, seconds: TimeInterval) -> (games: Int, flourishes: Int) {
        var games = 0, flourishes = 0
        var context = roaming()
        context.energy = energy
        let fidgets: Set<PetAnimationID> = [.blink, .lookLeft, .lookRight, .tailWag, .breathe, .yawn, .stretch, .blep, .hop, .snicker, .pounce]
        for seed in UInt64(1)...40 {
            var brain = PetBrain(now: t0, seed: seed)
            var t: TimeInterval = 0
            brain.update(context, now: t0)
            var playing = false
            var fidgeting: PetAnimationID?
            while t < seconds, let next = brain.nextWakeup(context: context, now: at(t)) {
                t = next.timeIntervalSince(t0)
                guard t < seconds else { break }
                brain.update(context, now: at(t))
                if brain.mischief != nil, !playing { games += 1 }
                playing = brain.mischief != nil
                let animation = brain.presentation.animation
                let now: PetAnimationID? = brain.presentation.mood == .idle && fidgets.contains(animation) ? animation : nil
                if let now, now != fidgeting { flourishes += 1 }
                fidgeting = now
            }
        }
        return (games, flourishes)
    }

    @Test("energy scales how often it plays and fidgets: calm < normal < playful, deterministically")
    func energyScalesTheSchedule() {
        let calm = liveliness(.calm, seconds: 85)
        let normal = liveliness(.normal, seconds: 85)
        let playful = liveliness(.playful, seconds: 85)
        #expect(calm.games < normal.games && normal.games < playful.games, "games: \(calm.games) \(normal.games) \(playful.games)")
        #expect(playful.games >= normal.games * 3 / 2)
        #expect(calm.games * 3 <= normal.games * 2)
        #expect(calm.flourishes < normal.flourishes, "flourishes: \(calm.flourishes) \(normal.flourishes)")
        // The same seeds, the same answer.
        #expect(liveliness(.playful, seconds: 85) == playful)
        #expect(PetEnergy.calm.mischiefPace > 1 && PetEnergy.playful.mischiefPace < 1 && PetEnergy.normal.mischiefPace == 1)
        #expect(PetEnergy.calm.flourishPace > 1 && PetEnergy.playful.flourishPace < 1 && PetEnergy.normal.flourishPace == 1)
    }

    @Test("normal energy is the pet as it always was; calm mostly sits and breathes")
    func energyNormalAndCalm() {
        // Normal, said out loud, is the default: the same life, beat for beat.
        for seed in [UInt64(2), 21] {
            var plain = PetBrain(now: t0, seed: seed)
            var chosen = PetBrain(now: t0, seed: seed)
            var context = roaming()
            let a = trace(&plain, context, until: 200)
            context.energy = .normal
            let b = trace(&chosen, context, until: 200)
            #expect(a.map(\.0) == b.map(\.0) && a.map(\.1) == b.map(\.1))
        }
        // Calm: its idle fidgets are the quiet ones only.
        var context = roaming()
        context.energy = .calm
        let quiet: Set<PetAnimationID> = [.sit, .blink, .breathe, .tailWag, .yawn]
        for seed in UInt64(1)...12 {
            var brain = PetBrain(now: t0, seed: seed)
            for (_, seen) in trace(&brain, context, until: 80) where seen.mood == .idle {
                #expect(quiet.contains(seen.animation), "a calm pet did \(seen.animation)")
            }
        }
    }

    @Test("energy sets how soon it dozes: calm at 90 s, normal at 3 min, playful at 6")
    func energySetsSleep() {
        #expect(PetEnergy.normal.sleepAfter == PetBrain.sleepAfter)
        #expect(PetEnergy.calm.sleepAfter == 90 && PetEnergy.playful.sleepAfter == 360)
        for energy in PetEnergy.allCases {
            var context = PetContext()
            context.energy = energy
            var brain = PetBrain(now: t0, seed: 1)
            brain.update(context, now: t0)
            brain.update(context, now: at(energy.sleepAfter - 1))
            #expect(brain.presentation.mood != .sleeping, "\(energy) fell asleep early")
            brain.update(context, now: at(energy.sleepAfter + 0.1))
            #expect(brain.presentation.mood == .sleeping, "\(energy) is still up")
            // And it is on the brain's schedule: nothing polls.
            var fresh = PetBrain(now: t0, seed: 1)
            fresh.update(context, now: t0)
            var t: TimeInterval = 0
            while fresh.presentation.mood != .sleeping, t < 400, let next = fresh.nextWakeup(context: context, now: at(t)) {
                t = next.timeIntervalSince(t0)
                fresh.update(context, now: at(t))
            }
            #expect(abs(t - energy.sleepAfter) < 0.2, "\(energy) fell asleep at \(t)")
        }
    }

    @Test("a change of energy takes effect at once, not after the old schedule runs out")
    func energyChangesLive() {
        var context = roaming()
        context.energy = .calm
        var brain = PetBrain(now: t0, seed: 9)
        brain.update(context, now: t0)
        context.energy = .playful
        brain.update(context, now: at(1))
        var t: TimeInterval = 1
        while brain.mischief == nil, t < 60, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
        }
        // A playful pet is at it within its settle time (12 s × 0.4), not calm's.
        #expect(brain.mischief != nil && t <= 1 + 12 * PetEnergy.playful.mischiefPace + 4, "first game at \(t)")
    }

    // MARK: - Night

    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A moment on 2026-03-10 (UTC).
    func clock(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    @Test("the night's hours: past midnight, within a day, and never when they are equal")
    func nightWindow() {
        let night = PetNight(startHour: 22, endHour: 7)
        for hour in [22, 23, 0, 3, 6] { #expect(night.contains(hour: hour), "\(hour)") }
        for hour in [7, 8, 12, 18, 21] { #expect(!night.contains(hour: hour), "\(hour)") }
        #expect(night.contains(clock(23, 59), calendar: utc) && night.contains(clock(0, 0), calendar: utc))
        #expect(night.contains(clock(6, 59), calendar: utc) && !night.contains(clock(7, 0), calendar: utc))
        #expect(!night.contains(clock(21, 59), calendar: utc) && night.contains(clock(22, 0), calendar: utc))
        let nap = PetNight(startHour: 13, endHour: 15)
        #expect(nap.contains(hour: 13) && nap.contains(hour: 14) && !nap.contains(hour: 15) && !nap.contains(hour: 12) && !nap.contains(hour: 2))
        let never = PetNight(startHour: 9, endHour: 9)
        #expect((0..<24).allSatisfy { !never.contains(hour: $0) })
        #expect(never.nextChange(after: clock(3), calendar: utc) == nil)
        // Hours are kept on the clock.
        #expect(PetNight(startHour: 40, endHour: -3) == PetNight(startHour: 23, endHour: 0))
        // The next time it begins or ends.
        #expect(night.nextChange(after: clock(20), calendar: utc) == clock(22))
        #expect(night.nextChange(after: clock(23, 30), calendar: utc) == clock(7, day: 11))
        #expect(night.nextChange(after: clock(3), calendar: utc) == clock(7))
        #expect(night.nextChange(after: clock(7), calendar: utc) == clock(22))
        #expect(night.label == "22:00 – 07:00")
        // The same hours read on the user's own clock, whatever its zone.
        var tokyo = utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(!night.contains(clock(23), calendar: tokyo)) // 08:00 in Tokyo
        #expect(night.contains(clock(14), calendar: tokyo)) // 23:00 in Tokyo
    }

    @Test("at night it curls up whatever the Mac is doing — unless NEO is active or the user is with it")
    func sleepsAtNight() {
        var context = PetContext()
        context.night = PetNight(startHour: 22, endHour: 7)
        context.isMusicPlaying = true // by day this keeps it up, dancing
        let start = clock(23)
        var brain = PetBrain(now: start, seed: 1)
        brain.calendar = utc
        brain.update(context, now: start)
        #expect(brain.presentation.mood == .music) // just arrived: not yet settled
        brain.update(context, now: start.addingTimeInterval(PetBrain.nightSettle + 0.1))
        #expect(brain.presentation.mood == .sleeping)
        #expect([.sleep, .sleepZzz].contains(brain.presentation.animation))

        // NEO starts listening: it wakes (a moment, as ever) into NEO's pose.
        var neo = context
        neo.neoState = .listening
        brain.update(neo, now: start.addingTimeInterval(60))
        #expect(brain.presentation.mood == .neo)
        brain.update(neo, now: start.addingTimeInterval(62))
        #expect(brain.presentation.mood == .neo && brain.presentation.animation == .neoListen)
        // NEO done: awake for the settle time, then asleep again.
        brain.update(context, now: start.addingTimeInterval(70))
        #expect(brain.presentation.mood != .sleeping)
        brain.update(context, now: start.addingTimeInterval(70 + PetBrain.nightSettle + 0.1))
        #expect(brain.presentation.mood == .sleeping)

        // The cursor comes to the island: it wakes (a moment, not a cut) and looks.
        var hovering = context
        hovering.isHovering = true
        brain.update(hovering, now: start.addingTimeInterval(200))
        #expect(brain.presentation.mood == .curious)
        brain.update(hovering, now: start.addingTimeInterval(260))
        #expect(brain.presentation.mood == .curious) // however long the user stays
        brain.update(context, now: start.addingTimeInterval(261))
        brain.update(context, now: start.addingTimeInterval(261 + PetBrain.nightSettle - 1))
        #expect(brain.presentation.mood != .sleeping)
        brain.update(context, now: start.addingTimeInterval(262 + PetBrain.nightSettle))
        #expect(brain.presentation.mood == .sleeping)

        // A click on it (its panel) keeps it up too.
        brain.handle(.petClicked, context: context, now: start.addingTimeInterval(400))
        brain.update(context, now: start.addingTimeInterval(405))
        #expect(brain.presentation.mood != .sleeping)
        var panel = context
        panel.interactionOpen = true
        brain.update(panel, now: start.addingTimeInterval(500))
        #expect(brain.presentation.mood == .interaction)
        // A call is a call, at any hour.
        var call = context
        call.inMeeting = true
        brain.update(call, now: start.addingTimeInterval(600))
        #expect(brain.presentation.mood == .meeting)
    }

    @Test("the night ends on the clock: morning comes on the brain's own schedule, and by day nothing changes")
    func nightEndsOnSchedule() {
        var context = PetContext()
        context.night = PetNight(startHour: 22, endHour: 7)
        context.isMusicPlaying = true
        // 21:59: day. It dances, and its next moment is no later than 22:00.
        var brain = PetBrain(now: clock(21, 59), seed: 1)
        brain.calendar = utc
        brain.update(context, now: clock(21, 59))
        #expect(brain.presentation.mood == .music)
        var now = clock(21, 59)
        var steps = 0
        while brain.presentation.mood != .sleeping, steps < 200, let next = brain.nextWakeup(context: context, now: now) {
            now = next
            brain.update(context, now: now)
            steps += 1
        }
        #expect(brain.presentation.mood == .sleeping)
        #expect(now >= clock(22) && now <= clock(22, 1), "asleep at \(now)")
        // Through the night (past midnight) it sleeps; at 07:00 it is up again — woken by the schedule alone.
        steps = 0
        while brain.presentation.mood == .sleeping || brain.presentation.animation == .wake, steps < 5000,
              let next = brain.nextWakeup(context: context, now: now) {
            #expect(next > now)
            now = next
            brain.update(context, now: now)
            steps += 1
            if now < clock(7, day: 11) {
                #expect(brain.presentation.mood == .sleeping, "awake at \(now)")
            }
        }
        #expect(now >= clock(7, day: 11) && now <= clock(7, 1, day: 11), "up at \(now)")
        #expect(brain.presentation.mood == .music)

        // By day the setting changes nothing: the same life as without it.
        var plain = PetBrain(now: t0, seed: 4)
        var withNight = PetBrain(now: t0, seed: 4)
        withNight.calendar = utc
        // t0 is 17:20 UTC; a night that is hours away.
        var day = roaming()
        let a = trace(&plain, day, until: 170)
        day.night = PetNight(startHour: 22, endHour: 7)
        let b = trace(&withNight, day, until: 170)
        #expect(a.map(\.1) == b.map(\.1))
        // Off (`nil`) is off even at midnight.
        var off = PetContext()
        off.isMusicPlaying = true
        var owl = PetBrain(now: clock(1), seed: 1)
        owl.calendar = utc
        owl.update(off, now: clock(1))
        owl.update(off, now: clock(1, 30))
        #expect(owl.presentation.mood == .music)
    }

    // MARK: - The panel

    @Test("the panel keeps every look's swatch and the hat button, and adds “more…” — in the title row, clear of the hello")
    func panelMore() {
        for frame in [geometry.skinFrame, geometry.petPanelFrame] {
            let layout = PetPanelLayout.layout(in: frame, notchInset: 32)
            #expect(layout.looks.map(\.look) == PetLook.allCases)
            #expect(frame.contains(layout.more))
            #expect(layout.more.maxY <= frame.maxY - 32)
            #expect(layout.more.maxX < layout.looks[0].rect.minX && layout.looks.last!.rect.maxX < layout.hat.minX)
            #expect(layout.more.midY == layout.looks[0].rect.midY)
            #expect(PetPanelLayout.hit(at: CGPoint(x: layout.more.midX, y: layout.more.midY), in: frame, notchInset: 32) == .more)
            for other in layout.looks.map(\.rect) + layout.actions.map(\.rect) + [layout.hat, layout.pet] {
                #expect(!layout.more.intersects(other))
            }
            // The hello keeps room beside the controls: "Hi, I'm Neo!" at 14 pt is about 90 pt wide.
            let titleMinX = layout.actions[0].rect.minX
            #expect(layout.more.minX - titleMinX >= 100)
            #expect(PetPanelLayout.greetingWidth >= 100 && PetPanelLayout.greetingWidth <= layout.more.minX - titleMinX)
        }
    }
}
