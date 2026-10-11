import Accelerate
import CoreGraphics
import NotchHubCore
import SwiftUI

/// The shape of the wake light's haze round one island, as a mask: how much
/// of the haze each pixel of the light's canvas shows, 0 … 1 — the island
/// grown `NeoWakeLight.hazeLift` and blurred by a true Gaussian
/// (`hazeRadius`); the light clips the island itself out, as a vector, in
/// either case. The light at rest fills its colour along the rim and
/// multiplies it by this, so it needs no blur pass a frame. While the
/// island springs every frame is a new island, so the light blurs the same
/// shape on the GPU instead (`blurRadius` makes that the same Gaussian), and
/// once the island holds still it hands over to the mask gently
/// (`NeoWakeLight.HazeSettling`, kept per view by a `Tracker`).
///
/// MADE OFF THE MAIN THREAD, AT HALF RESOLUTION: the mask is asked for the
/// first frame the island holds still, and made on a background task —
/// the light keeps the GPU's blur until it is ready (a few milliseconds),
/// rather than holding up that frame for it. It is made at half the
/// display's resolution (`maskResolution`): under a blur of 10 device
/// pixels its pixels are invisible, and it costs a quarter as much to make,
/// keep and draw. Offscreen renders, whose island never moves, make it at
/// once (`maskNow`).
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

    /// The mask's pixels per device pixel.
    static let maskResolution: CGFloat = 0.5

    /// `--neo-outline-frames … --outline-haze shaped|mask`: the settled
    /// haze drawn only from the GPU's blurred shape, or only from the mask,
    /// so that the two can be compared. `nil` (always, live): as the light
    /// decides.
    enum Way: String { case shaped, mask }
    static var forced: Way?

    /// The masks made, newest last: one per shape the island rests in.
    private static var cache: [(key: Key, image: CGImage)] = []
    private static let capacity = 6
    /// The masks being made, so each is made once.
    private static var pending: [Key] = []

    /// The radius to ask SwiftUI's blur for so that it is the mask's
    /// Gaussian — standard deviation `hazeRadius` — and the GPU's haze and
    /// the mask's can be swapped without the haze changing. SwiftUI's blur
    /// is a Gaussian, but not of standard deviation `radius` exactly, nor
    /// the same in every renderer: fitted to a blurred hard edge at 2×, its
    /// standard deviation is 0.99 × radius drawn live (on screen, and as
    /// `cacheDisplay` samples it) and 0.934 × radius in an `ImageRenderer`
    /// (the offscreen frames). Asked for 5, the offscreen haze was 7 %
    /// narrower than the mask's.
    static func blurRadius(offscreen: Bool) -> CGFloat {
        CGFloat(NeoWakeLight.hazeRadius / (offscreen ? 0.934 : 0.99))
    }

    /// One view's haze: whether its island holds still, and how far it has
    /// handed over to the mask. Kept by the view (in `@State`), so two
    /// islands drawn in turn never take each other for a move.
    final class Tracker {
        private var settling = NeoWakeLight.HazeSettling<Key>()

        /// The mask for the island drawn at `time` (the frame's time) and
        /// its share of the settled haze — or `nil` while the island moves
        /// or its mask is being made (and asks for it the first frame the
        /// island holds still).
        @MainActor
        func mask(for key: Key, shape: NotchShape, at time: TimeInterval) -> (image: CGImage, share: Double)? {
            guard settling.still(key, at: time) else {
                _ = settling.maskShare(ready: false, at: time)
                return nil
            }
            guard let image = NeoWakeHaze.cached(key) else {
                NeoWakeHaze.request(key, shape: shape)
                _ = settling.maskShare(ready: false, at: time)
                return nil
            }
            return (image, settling.maskShare(ready: true, at: time))
        }
    }

    /// The mask for `key` if it has been made (and keeps it the newest).
    static func cached(_ key: Key) -> CGImage? {
        guard let index = cache.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = cache.remove(at: index)
        cache.append(entry)
        return entry.image
    }

    /// Offscreen: the mask for `key`, made now if need be.
    static func maskNow(for key: Key, shape: NotchShape) -> CGImage? {
        if let image = cached(key) { return image }
        guard let image = make(source(key, shape: shape), canvas: key.canvas, scale: key.scale * maskResolution) else { return nil }
        keep(image, for: key)
        return image
    }

    /// Asks for the mask for `key`, made on a background task.
    static func request(_ key: Key, shape: NotchShape) {
        guard !pending.contains(key) else { return }
        pending.append(key)
        let path = source(key, shape: shape)
        let canvas = key.canvas, scale = key.scale * maskResolution
        Task.detached(priority: .userInitiated) {
            let image = make(path, canvas: canvas, scale: scale)
            await MainActor.run {
                pending.removeAll { $0 == key }
                if let image { keep(image, for: key) }
            }
        }
    }

    private static func keep(_ image: CGImage, for key: Key) {
        cache.removeAll { $0.key == key }
        cache.append((key, image))
        if cache.count > capacity { cache.removeFirst(cache.count - capacity) }
    }

    /// Draws `source` (in the canvas's points, top-left origin) at `scale`
    /// pixels a point and blurs it.
    nonisolated static func make(_ source: CGPath, canvas: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((canvas.width * scale).rounded(.up)), height = Int((canvas.height * scale).rounded(.up))
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
        context.addPath(source)
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

    /// The haze's shape before the blur, for the mask.
    static func source(_ key: Key, shape: NotchShape) -> CGPath {
        coverage(NotchRimGeometry(shape, in: key.island), grown: CGFloat(NeoWakeLight.hazeLift)).cgPath
    }

    /// The whole island grown `grown` points, up to just above the screen's
    /// top edge: ONE contour — down the leading half, round the bottom, up
    /// the trailing half and back across the top — so no edge runs through
    /// it to leave a line of lower coverage where two pieces would abut.
    static func coverage(_ rim: NotchRimGeometry, grown: CGFloat) -> Path {
        let leading = rim.half(.leading, offset: grown)
        let trailing = rim.half(.trailing, offset: grown)
        var path = Path()
        NotchRimGeometry.add(leading, to: &path, moving: true)
        NotchRimGeometry.add(trailing.reversed().map(\.reversed), to: &path, moving: false)
        let top = rim.rect.minY - 1
        path.addLine(to: CGPoint(x: trailing.first?.start.x ?? rim.rect.maxX, y: top))
        path.addLine(to: CGPoint(x: leading.first?.start.x ?? rim.rect.minX, y: top))
        path.closeSubpath()
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
