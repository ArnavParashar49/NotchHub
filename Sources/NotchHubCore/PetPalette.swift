import Foundation

/// Colour arithmetic for the pet's palettes: sRGB ⇄ HSL, relative luminance
/// and the WCAG contrast ratio. Colours are 0xRRGGBB.
public enum PetColor {

    /// The island's black, which every palette must read against.
    public static let black: UInt32 = 0x000000

    public static func components(_ rgb: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }

    public static func rgb(r: Double, g: Double, b: Double) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG relative luminance, 0 (black) … 1 (white).
    public static func luminance(_ rgb: UInt32) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let c = components(rgb)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// WCAG contrast ratio between two colours, 1 … 21.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// HSL (each 0 … 1; the hue wraps) → 0xRRGGBB.
    public static func hsl(_ h: Double, _ s: Double, _ l: Double) -> UInt32 {
        let hue = (h - h.rounded(.down)) * 6
        let sat = min(1, max(0, s)), light = min(1, max(0, l))
        let chroma = (1 - abs(2 * light - 1)) * sat
        let x = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let m = light - chroma / 2
        let (r, g, b): (Double, Double, Double)
        switch Int(hue) {
        case 0: (r, g, b) = (chroma, x, 0)
        case 1: (r, g, b) = (x, chroma, 0)
        case 2: (r, g, b) = (0, chroma, x)
        case 3: (r, g, b) = (0, x, chroma)
        case 4: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        return rgb(r: r + m, g: g + m, b: b + m)
    }
}

/// A fur colour the user picked: hue, saturation and lightness, each 0 … 1.
/// What is DRAWN is derived from it within bounds (`PetPalette.custom`), so
/// no pick can make the fox unreadable on the island's black.
public struct PetFurColor: Codable, Equatable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var lightness: Double

    public init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = Self.unit(hue)
        self.saturation = Self.unit(saturation)
        self.lightness = Self.unit(lightness)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hue: try container.decode(Double.self, forKey: .hue),
            saturation: try container.decode(Double.self, forKey: .saturation),
            lightness: try container.decode(Double.self, forKey: .lightness)
        )
    }

    /// A soft violet: unlike every preset, so "Custom" starts somewhere new.
    public static let `default` = PetFurColor(hue: 0.72, saturation: 0.62, lightness: 0.66)

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

/// The colours the fox is drawn in: the art's base colours mapped to a look's
/// or to a ramp derived from a custom fur colour. Built when the settings
/// change — never per frame — and looked up per run while drawing. Props,
/// effects, hats and accessories keep their own colours: only the fox's keys
/// are mapped.
public struct PetPalette: Equatable, Sendable {
    /// Base colour → drawn colour, for the colours that change.
    public let map: [UInt32: UInt32]

    public init(map: [UInt32: UInt32]) {
        self.map = map
    }

    /// The colour a pixel of `rgb` is drawn in.
    public func color(_ rgb: UInt32) -> UInt32 {
        map[rgb] ?? rgb
    }

    /// The art's own orange fox.
    public static let fox = PetPalette(map: [:])

    /// A preset look's palette (`art/pet/looks.txt`).
    public static func look(_ look: PetLook) -> PetPalette {
        PetPalette(map: look.colorMap)
    }

    // The fox's keys in the art's palette.
    static func base(_ key: Character, _ fallback: UInt32) -> UInt32 { PetArt.palette[key] ?? fallback }
    public static let baseFur = base("o", 0xE97A2E)
    public static let baseShade = base("O", 0xB9541D)
    public static let baseHighlight = base("y", 0xF7A657)
    public static let baseOutline = base("k", 0x2A1810)
    public static let baseCream = base("w", 0xFFF3E2)
    public static let baseCreamShade = base("W", 0xD9C4A5)
    public static let baseEyes = base("e", 0x17100D)

    public var fur: UInt32 { color(Self.baseFur) }
    public var shade: UInt32 { color(Self.baseShade) }
    public var highlight: UInt32 { color(Self.baseHighlight) }
    public var outline: UInt32 { color(Self.baseOutline) }
    public var cream: UInt32 { color(Self.baseCream) }
    public var creamShade: UInt32 { color(Self.baseCreamShade) }
    public var eyes: UInt32 { color(Self.baseEyes) }

    // MARK: - Custom fur

    /// The fur's luminance is kept inside this band: at the bottom it is still
    /// 4:1 against the island's black and 3:1 against the dark eyes and the
    /// outline; at the top the cream muzzle, chest and tail tip still stand
    /// clear of it.
    public static let furLuminance: ClosedRange<Double> = 0.16...0.60
    /// The outline is the fur's own hue, nearly black.
    static let outlineLightness = 0.09
    static let outlineSaturation = 0.5

    /// The fur colour actually drawn for a pick: the same hue and saturation,
    /// its lightness moved just far enough to bring its luminance into
    /// `furLuminance`.
    public static func clampedFur(_ pick: PetFurColor) -> (rgb: UInt32, lightness: Double) {
        let h = pick.hue, s = pick.saturation
        func lum(_ l: Double) -> Double { PetColor.luminance(PetColor.hsl(h, s, l)) }
        var lightness = min(0.9, max(0.1, pick.lightness))
        let current = lum(lightness)
        if current < furLuminance.lowerBound || current > furLuminance.upperBound {
            // Luminance rises with lightness at a fixed hue and saturation.
            let target = current < furLuminance.lowerBound ? furLuminance.lowerBound + 0.005 : furLuminance.upperBound - 0.005
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let mid = (low + high) / 2
                if lum(mid) < target { low = mid } else { high = mid }
            }
            lightness = (low + high) / 2
        }
        return (PetColor.hsl(h, s, lightness), lightness)
    }

    /// The fox's shade ramp derived from a picked fur colour: the fur itself
    /// (clamped), a darker shade, a lighter highlight, and an outline of the
    /// same hue that is nearly black. Cream, eyes, nose and props keep the
    /// art's colours.
    public static func custom(_ pick: PetFurColor) -> PetPalette {
        let (fur, lightness) = clampedFur(pick)
        let h = pick.hue, s = pick.saturation
        let shade = PetColor.hsl(h, min(1, s * 1.05), lightness * 0.74)
        let highlight = PetColor.hsl(h, s, lightness + (1 - lightness) * 0.32)
        let outline = PetColor.hsl(h, min(s, outlineSaturation), outlineLightness)
        return PetPalette(map: [
            baseFur: fur,
            baseShade: shade,
            baseHighlight: highlight,
            baseOutline: outline,
        ])
    }
}

/// The tint for NEO's wake outline, kept under its old settings name for saved preferences.
public enum PetGlowColor: String, CaseIterable, Codable, Sendable {
    /// The design system's cyan-teal (`DesignTokens.listeningGlow`).
    case teal
    case sky
    case violet
    case rose
    case amber
    case white
    /// The fur's own highlight colour.
    case matchFur

    public var title: String {
        switch self {
        case .teal: return "Teal"
        case .sky: return "Sky"
        case .violet: return "Violet"
        case .rose: return "Rose"
        case .amber: return "Amber"
        case .white: return "White"
        case .matchFur: return "Match fur"
        }
    }

    /// The glow's colour with a fox drawn in `palette`; `nil` is the design
    /// token's teal, untouched.
    public func rgb(palette: PetPalette) -> UInt32? {
        switch self {
        case .teal: return nil
        case .sky: return 0x6FA8FF
        case .violet: return 0xB18CFF
        case .rose: return 0xFF7FA8
        case .amber: return 0xFFC24D
        case .white: return 0xF2F6FF
        case .matchFur: return Self.lit(palette.highlight)
        }
    }

    /// A colour as light: a dark fur glows in its own hue, lifted until it is
    /// bright enough to be seen as a glow on black.
    static func lit(_ rgb: UInt32) -> UInt32 {
        guard PetColor.luminance(rgb) < 0.35 else { return rgb }
        let c = PetColor.components(rgb)
        var mix = 0.0
        var result = rgb
        while PetColor.luminance(result) < 0.35, mix < 1 {
            mix += 0.05
            result = PetColor.rgb(r: c.r + (1 - c.r) * mix, g: c.g + (1 - c.g) * mix, b: c.b + (1 - c.b) * mix)
        }
        return result
    }
}
