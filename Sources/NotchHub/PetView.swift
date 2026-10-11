import NotchHubCore
import SwiftUI

/// What the island shows of the pet.
struct PetRenderModel: Equatable {
    var presentation: PetPresentation
    var look: PetLook = .fox
    var hat: PetHat? = nil
    /// The colours the fox is drawn in, when they are not simply `look`'s (a
    /// custom fur colour). Derived when the settings change, never per frame.
    var palette: PetPalette? = nil
    /// What it wears besides its hat.
    var accessory: PetAccessory? = nil
    /// How big it is in the notch strip: where every shape places it, and the
    /// room the bars keep for it.
    var size: PetSize = .normal
    /// The wake outline's tint (0xRRGGBB); `nil` is the design token's teal.
    var glow: UInt32? = nil
    /// What it is called, for assistive technology.
    var name: String = PetIdentity.name
}

/// Draws the pixel pet.
///
/// At the normal size every art pixel is a whole number of points (1× in the
/// notch bar, 2× in the expanded island — 2 or 4 device pixels on Retina),
/// filled WITHOUT anti-aliasing, and every movement is a whole number of art
/// pixels, so edges stay razor sharp at any position. At the small and large
/// sizes an art pixel is a fraction of a point: each pixel's edges are snapped
/// to device pixels (nearest-neighbour — never smoothed) and every movement is
/// rounded to whole points, so the art stays as crisp and never shimmers. The view redraws only while its animation
/// still has frames to show (`PetFrameSchedule`): a still pose draws once, and a
/// looping one ticks at the animation's own frame rate.
struct PetView: View {
    let presentation: PetPresentation
    /// Points per art pixel: a whole number at the normal size.
    let scale: CGFloat
    /// The fox's colours.
    var look: PetLook = .fox
    /// What it wears on its head.
    var hat: PetHat? = nil
    /// Its colours when they are not simply `look`'s (a custom fur colour).
    var palette: PetPalette? = nil
    /// What it wears besides its hat.
    var accessory: PetAccessory? = nil
    /// What it is called.
    var name: String = PetIdentity.name

    var body: some View {
        let animation = presentation.animation.animation
        let start = presentation.startedAt
        // ONE timeline for every kind of pose, so a change of pose keeps this
        // view's identity: when the island moves, the pet's move from where it
        // was drawn rides the island's spring instead of jumping.
        TimelineView(PetFrameSchedule(start: start, animation: animation)) { context in
            cel(animation, frame: animation.frameIndex(at: context.date.timeIntervalSince(start)))
        }
        .frame(width: PetLayout.artSize * scale, height: PetLayout.artSize * scale)
        .accessibilityElement()
        .accessibilityLabel(name)
    }

    /// One frame, drawn where the animation puts it. On the left of the notch
    /// the whole presentation is mirrored: the art flips and moves the other way.
    private func cel(_ animation: PetAnimation, frame index: Int) -> some View {
        let mirrored = presentation.mirrored
        let offset = animation.offset(forFrame: index)
        return PetCanvas(frameName: PetFrame.name(animation.frames[index], mirrored: mirrored), scale: scale,
                         palette: palette ?? .look(look), hat: hat, accessory: accessory)
            .offset(x: PetMetrics.points(mirrored ? -offset.dx : offset.dx, scale: scale), y: PetMetrics.points(offset.dy, scale: scale))
    }
}

/// When the pet's view redraws: once for a still pose, once per frame for a
/// one-shot (then never again), and every frame for a loop.
struct PetFrameSchedule: TimelineSchedule {
    let start: Date
    let frameDuration: TimeInterval
    let frameCount: Int
    let loops: Bool

    init(start: Date, animation: PetAnimation) {
        self.start = start
        frameDuration = animation.frameDuration
        frameCount = animation.frames.count
        loops = animation.loops
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let start = start
        let frameDuration = frameDuration
        guard frameCount > 1, frameDuration > 0 else {
            var done = false
            return AnyIterator {
                defer { done = true }
                return done ? nil : start
            }
        }
        if loops {
            var index = Int((max(0, startDate.timeIntervalSince(start)) / frameDuration).rounded(.down))
            return AnyIterator {
                defer { index += 1 }
                return start.addingTimeInterval(Double(index) * frameDuration)
            }
        }
        let count = frameCount
        var index = 0
        return AnyIterator {
            guard index < count else { return nil }
            defer { index += 1 }
            return start.addingTimeInterval(Double(index) * frameDuration)
        }
    }
}

/// One frame, as runs of rectangles: the fox in its palette, what it wears on
/// the frame's wear anchor, and its hat on the frame's head anchor. The drawing
/// reaches `headroom` art pixels above the frame (a hat may stand that tall)
/// without changing its layout.
///
/// Nothing is allocated to recolour a frame: the palette is a table built when
/// the settings change, looked up per run.
struct PetCanvas: View, Equatable {
    let frameName: String
    let scale: CGFloat
    var palette: PetPalette = .fox
    var hat: PetHat? = nil
    var accessory: PetAccessory? = nil

    static let headroom = 8

    var body: some View {
        let size = PetLayout.artSize * scale
        let top = CGFloat(Self.headroom)
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            guard let frame = PetFrame.named(frameName) ?? PetFrame.named("sit") else { return }
            // A fractional scale snaps every pixel edge to the device's grid.
            let grid: CGFloat = scale == scale.rounded() ? 0 : max(1, context.environment.displayScale)
            for run in frame.runs {
                fill(run, color: palette.color(run.color), top: top, grid: grid, in: &context)
            }
            if let accessory {
                for run in PetFrame.accessoryRuns(accessory, on: frameName) {
                    fill(run, color: run.color, top: top, grid: grid, in: &context)
                }
            }
            if let hat {
                for run in PetFrame.hatRuns(hat, on: frameName) where run.y >= -Self.headroom {
                    fill(run, color: run.color, top: top, grid: grid, in: &context)
                }
            }
        }
        .frame(width: size, height: size + top * scale)
        .frame(width: size, height: size, alignment: .bottom)
    }

    private func fill(_ run: PetFrame.Run, color: UInt32, top: CGFloat, grid: CGFloat, in context: inout GraphicsContext) {
        let rect: CGRect
        if grid == 0 {
            rect = CGRect(
                x: CGFloat(run.x) * scale,
                y: (CGFloat(run.y) + top) * scale,
                width: CGFloat(run.length) * scale,
                height: scale
            )
        } else {
            // Nearest-neighbour: each edge lands on a device pixel, and a run
            // ends exactly where the next begins.
            func edge(_ pixel: CGFloat) -> CGFloat { PetMetrics.pixelEdge(pixel, scale: scale, grid: grid) }
            let minX = edge(CGFloat(run.x))
            let maxX = edge(CGFloat(run.x + run.length))
            let minY = edge(CGFloat(run.y) + top)
            let maxY = edge(CGFloat(run.y) + top + 1)
            rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        context.fill(Path(rect), with: .color(Self.color(color)), style: FillStyle(antialiased: false))
    }

    static func color(_ rgb: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
