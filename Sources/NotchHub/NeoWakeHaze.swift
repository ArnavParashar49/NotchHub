import Accelerate
import CoreGraphics
import NotchHubCore
import SwiftUI

/// The shape of the wake light's haze round one island, as a mask: how much
/// of the haze each device pixel of the light's canvas shows, 0 … 1 — the
/// island grown `NeoWakeLight.hazeLift` and blurred by a true Gaussian
/// (`hazeRadius`); the light clips the island itself out, as a vector, in
/// either case. It is the same blur the springing path draws on the GPU
/// (`NeoWakeRim`), made once on the CPU (vImage) and kept, so that the
/// settled light — which changes every frame but whose island does not —
/// needs no blur pass a frame: it fills its light along the rim and
/// multiplies it by this. (The difference from blurring the light itself:
/// the light's colour along the rim is not smeared sideways by 5 pt — at
/// the highlight's breadth, a tenth of the island, invisible.)
///
/// While the island springs between shapes every frame is a new island, so
/// the light blurs on the GPU instead (`mask(for:)` returns `nil` until the
/// island has held still for a frame); offscreen renders always use the mask.
@MainActor
enum NeoWakeHaze {

    /// One island as the light's canvas sees it, in points, and the scale.
    struct Key: Equatable {
        var canvas: CGSize
        var island: CGRect
        var radii: NotchShape.AnimatableData
        var scale: CGFloat

        init(canvas: CGSize, island: CGRect, shape: NotchShape, scale: CGFloat) {
            self.canvas = canvas
            self.island = island
            radii = shape.animatableData
            self.scale = scale
        }
    }

    /// The masks made, newest last: one per shape the island rests in.
    private static var cache: [(key: Key, image: CGImage)] = []
    private static let capacity = 6
    /// The island the last frame was drawn round.
    private static var previous: Key?

    /// For the light drawn round `key`: the mask, made now if the island
    /// has held still since the last frame (or `always`, offscreen), or
    /// `nil` while it is moving.
    static func mask(for key: Key, shape: NotchShape, always: Bool) -> CGImage? {
        defer { previous = key }
        if let index = cache.firstIndex(where: { $0.key == key }) {
            let entry = cache.remove(at: index)
            cache.append(entry)
            return entry.image
        }
        guard always || previous == key, let image = make(key, shape: shape) else { return nil }
        cache.append((key, image))
        if cache.count > capacity { cache.removeFirst(cache.count - capacity) }
        return image
    }

    /// Draws the island grown by the lift and blurs it.
    static func make(_ key: Key, shape: NotchShape) -> CGImage? {
        let scale = key.scale
        let width = Int((key.canvas.width * scale).rounded(.up)), height = Int((key.canvas.height * scale).rounded(.up))
        // Drawn and blurred as coverage alone, one byte a pixel…
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data
        else { return nil }
        // Top-left origin, in points, as the canvas draws.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(gray: 0, alpha: 1)
        context.addPath(source(key, shape: shape).cgPath)
        context.fillPath()

        // The blur: a separable Gaussian, out to 3.5 standard deviations.
        let rowBytes = context.bytesPerRow
        var src = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        guard let blurred = malloc(rowBytes * height) else { return nil }
        defer { free(blurred) }
        var dst = vImage_Buffer(data: blurred, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        let sigma = Float(NeoWakeLight.hazeRadius * Double(scale))
        let reach = Int((sigma * 3.5).rounded(.up))
        var kernel = (-reach...reach).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        kernel = kernel.map { $0 / total }
        guard vImageSepConvolve_Planar8(&src, &dst, nil, 0, 0, kernel, UInt32(kernel.count), kernel, UInt32(kernel.count),
                                        0, 0, vImage_Flags(kvImageBackgroundColorFill)) == kvImageNoError
        else { return nil }
        // …and handed over as premultiplied RGBA, every channel the coverage
        // (white, at that alpha). Not as the alpha-only bitmap itself: some
        // of SwiftUI's renderers draw an alpha-only image as opaque, and the
        // haze's whole source — 19 pt of hard-edged light — would show
        // (seen in `--neo-outline-morph`, which snapshots the live view).
        guard let rgba = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = rgba.data
        else { return nil }
        var out = vImage_Buffer(data: pixels, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rgba.bytesPerRow)
        // The same plane for all four channels, so their order is moot.
        guard vImageConvert_Planar8toARGB8888(&dst, &dst, &dst, &dst, &out, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return nil }
        return rgba.makeImage()
    }

    /// The haze's source: the island grown by the lift, both halves.
    static func source(_ key: Key, shape: NotchShape) -> Path {
        let rim = NotchRimGeometry(shape, in: key.island)
        let split = key.island.width / 2
        var path = Path()
        for half in NeoWakeLight.Half.allCases {
            path.addPath(region(rim, half: half, split: split, grown: CGFloat(NeoWakeLight.hazeLift)))
        }
        return path
    }

    /// One half of the island grown `grown` points: from its top end down
    /// the grown rim to where the halves meet (`split`, from the island's
    /// left), up to just above the screen's top edge, and back.
    static func region(_ rim: NotchRimGeometry, half: NeoWakeLight.Half, split: CGFloat, grown: CGFloat) -> Path {
        let segments = rim.half(half, offset: grown, split: split)
        var path = Path()
        NotchRimGeometry.add(segments, to: &path, moving: true)
        let top = rim.rect.minY - 1
        path.addLine(to: CGPoint(x: rim.rect.minX + split, y: top))
        path.addLine(to: CGPoint(x: segments.first?.start.x ?? rim.rect.minX, y: top))
        path.closeSubpath()
        return path
    }
}
