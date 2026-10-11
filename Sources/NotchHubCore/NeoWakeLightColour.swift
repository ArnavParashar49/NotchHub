import Foundation

/// The wake light's colours, all derived from ONE tint — the design token's
/// blue, or whatever glow colour the user chose for their pet — so every
/// setting lights the rim the same way: a luminous line, a saturated glow
/// hugging it, and a deeper, darker haze bleeding out from it like a
/// planet's atmosphere seen edge-on from space.
///
/// The derivation is done in OKLCH (Björn Ottosson's OKLab, in polar form),
/// where lightness, chroma and hue are perceptually independent: lifting
/// the line's lightness does not wash its hue out, and deepening the haze
/// does not turn a blue purple. Every result is brought back inside sRGB by
/// lowering chroma only, so lightness and hue are what was asked for.
extension NeoWakeLight {

    /// A colour as sRGB components, 0 … 1.
    public struct Colour: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(_ rgb: (red: Double, green: Double, blue: Double)) {
            self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }

        /// From a packed 0xRRGGBB.
        public init(hex: UInt32) {
            self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255)
        }

        /// This colour moved `amount` (0 … 1) of the way to white, in sRGB.
        public func whitened(_ amount: Double) -> Colour {
            let w = NeoWakeLight.clamp(amount)
            return Colour(red: red + (1 - red) * w, green: green + (1 - green) * w, blue: blue + (1 - blue) * w)
        }

        public var hex: UInt32 {
            func byte(_ v: Double) -> UInt32 { UInt32((NeoWakeLight.clamp(v) * 255).rounded()) }
            return byte(red) << 16 | byte(green) << 8 | byte(blue)
        }
    }

    /// The light's four colours for one tint.
    public struct Palette: Equatable, Sendable {
        /// The line on the silhouette: the tint lifted towards its luminous
        /// side (a blue leans a touch to cyan), a little less saturated, and
        /// never more than `maxWhite` of the way to white — the hottest
        /// moments add that much at most (`Stop.white`).
        public var line: Colour
        /// The narrow glow hugging the line, outside: MORE saturated than the
        /// tint, so the edge reads as coloured light rather than white.
        public var near: Colour
        /// The broad haze bleeding outward from it: deeper and darker, the
        /// colour of the atmosphere's outer edge; drawn at low alpha.
        public var haze: Colour
        /// The faint rim light just inside the black, as if lit from behind.
        public var inner: Colour
    }

    /// How far towards white the line may ever go — at the sweep's head and
    /// the bloom. The resting line is the palette's own colour (its lean to
    /// white rests at `restWhite`).
    public static let maxWhite = 0.15
    public static let restWhite = 0.03

    /// The chroma from which a tint counts as fully coloured (a pastel's):
    /// below it, the extra saturation the glow and the haze are given fades
    /// out with the tint's own (`palette(tint:)`).
    public static let neutralChroma = 0.04

    /// The palette for `tint`.
    public static func palette(tint: Colour) -> Palette {
        let t = OKLCH(tint)
        // A blue (hues ~175°–315°) leans towards cyan at the line and deepens
        // at the haze — the horizon in a photograph from orbit runs from a
        // cyan line (h ≈ 210°) to a deep blue atmosphere (h ≈ 257°); other
        // hues keep their own all the way.
        let blueness = max(0, 1 - abs(angle(t.h, 245)) / 70)
        // How coloured the tint is: 0 for a white or a grey, 1 from a pastel
        // up. The glow and the haze are made a little richer than the tint
        // by ADDING chroma — but a neutral tint's hue is noise (atan2 of two
        // near-zeros: about 90°, yellow, for a pure grey), so added chroma
        // would turn a white glow khaki. It fades out with the tint's own.
        let colourful = min(1, t.c / neutralChroma)
        // The line is the tint lifted, capped at 0.85 so that a coloured
        // line keeps its colour (sRGB has little chroma left near white).
        // A neutral tint has no colour to keep: a light one may light a
        // near-white line rather than a grey one.
        let lineCap = 0.85 + (1 - colourful) * max(0, min(0.95, t.l) - 0.85)
        let line = OKLCH(l: min(lineCap, max(t.l + 0.15, 0.76)), c: t.c * 0.95, h: t.h - 18 * blueness)
        let near = OKLCH(l: min(0.76, max(t.l + 0.04, 0.64)), c: t.c * 1.15 + 0.02 * colourful, h: t.h - 8 * blueness)
        let haze = OKLCH(l: min(0.62, max(t.l - 0.06, 0.54)), c: t.c * 1.15 + 0.03 * colourful, h: t.h + 4 * blueness)
        let inner = OKLCH(l: min(0.80, max(t.l + 0.08, 0.68)), c: t.c, h: t.h - 14 * blueness)
        return Palette(line: line.srgb, near: near.srgb, haze: haze.srgb, inner: inner.srgb)
    }

    /// The signed difference between two hues, in degrees (-180 ..< 180).
    static func angle(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d >= 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// A colour in OKLCH: perceptual lightness `l` (0 … 1), chroma `c`, hue
    /// `h` in degrees.
    public struct OKLCH: Equatable, Sendable {
        public var l: Double
        public var c: Double
        public var h: Double

        public init(l: Double, c: Double, h: Double) {
            self.l = l
            self.c = max(0, c)
            self.h = h
        }

        public init(_ colour: Colour) {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let r = linear(colour.red), g = linear(colour.green), b = linear(colour.blue)
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            var hue = atan2(bb, a) * 180 / .pi
            if hue < 0 { hue += 360 }
            self.init(l: lightness, c: (a * a + bb * bb).squareRoot(), h: hue)
        }

        /// Linear sRGB, unclamped.
        func linearRGB(chroma: Double) -> (Double, Double, Double) {
            let a = chroma * cos(h * .pi / 180), b = chroma * sin(h * .pi / 180)
            let l_ = l + 0.3963377774 * a + 0.2158037573 * b
            let m_ = l - 0.1055613458 * a - 0.0638541728 * b
            let s_ = l - 0.0894841775 * a - 1.2914855480 * b
            let ll = l_ * l_ * l_, mm = m_ * m_ * m_, ss = s_ * s_ * s_
            return (4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
                    -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
                    -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss)
        }

        /// In sRGB, its chroma lowered (lightness and hue kept) until it fits.
        public var srgb: Colour {
            func fits(_ c: Double) -> Bool {
                let (r, g, b) = linearRGB(chroma: c)
                let e = 1e-6
                return r >= -e && r <= 1 + e && g >= -e && g <= 1 + e && b >= -e && b <= 1 + e
            }
            var chroma = c
            if !fits(chroma) {
                var lo = 0.0, hi = chroma
                for _ in 0..<32 {
                    let mid = (lo + hi) / 2
                    if fits(mid) { lo = mid } else { hi = mid }
                }
                chroma = lo
            }
            func encode(_ v: Double) -> Double {
                let x = NeoWakeLight.clamp(v)
                return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            }
            let (r, g, b) = linearRGB(chroma: chroma)
            return Colour(red: encode(r), green: encode(g), blue: encode(b))
        }
    }
}
