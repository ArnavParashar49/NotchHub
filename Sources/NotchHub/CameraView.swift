import AppKit
import AVFoundation
import NotchHubCore
import SwiftUI

@MainActor
final class NeoCameraStream: ObservableObject {
    @Published var frame: Data?
    @Published var boxes: [NeoCameraBox] = []
}

/// The camera preview and its quiet bar of controls. The manual notch camera
/// uses an `AVCaptureVideoPreviewLayer` and reads no frames; NEO's separate,
/// short-lived stream is shown only when NEO itself is looking through it.
/// Controls are drawn and hit-tested by the window, so the preview never pulls
/// focus from the app you are about to present from.
struct CameraView: View {
    let state: CameraState
    /// The live preview layer, when there is one.
    let previewLayer: AVCaptureVideoPreviewLayer?
    /// NEO's streamed camera surface. The manual notch camera leaves this nil
    /// and continues to use its native AVFoundation preview layer.
    var stream: NeoCameraStream? = nil
    /// A short NEO result or label shown over the native preview.
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controlBar
                .frame(height: CameraLayout.barHeight)
                .padding(.top, CameraLayout.pictureBottomGap)
                .padding(.bottom, CameraLayout.barBottomInset)
        }
        .padding(.horizontal, CameraLayout.horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Picture

    @ViewBuilder
    private var picture: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.radiusRow, style: .continuous)
                .fill(Color.white.opacity(0.05))

            if state.phase == .live, let stream {
                NeoCameraStreamPreview(stream: stream, mirrored: state.isMirrored)
                    .transition(.opacity)
            } else if state.phase == .live, let previewLayer {
                CameraPreview(layer: previewLayer)
                    // Mirrored the way you expect to see yourself. This flips
                    // the PREVIEW only; nothing is being captured to flip.
                    .scaleEffect(x: state.isMirrored ? -1 : 1, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusRow, style: .continuous))
                    .transition(.opacity)
            } else {
                placeholder
            }

            if let caption, !caption.isEmpty {
                VStack {
                    Spacer()
                    Text(caption)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(7)
                }
            }
        }
        .animation(DesignTokens.springMorph, value: state.phase)
    }

    /// What the picture area shows before there is a picture — or instead of
    /// one. Never an empty black hole with no explanation.
    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: placeholderSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFailed ? DesignTokens.warning : DesignTokens.textTertiary)
                .opacity(state.phase == .starting && !pulse ? 0.45 : 1)
                .animation(
                    state.phase == .starting
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
            Text(state.statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isFailed ? DesignTokens.warning : DesignTokens.textSecondary)
            Text(state.detailText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }

    @State private var pulse = false

    private var isFailed: Bool {
        if case .failed = state.phase { return true }
        return false
    }

    private var placeholderSymbol: String {
        switch state.phase {
        case let .failed(failure): return failure.isPermission ? "video.slash.fill" : "exclamationmark.triangle.fill"
        default: return "video.fill"
        }
    }

    // MARK: - Controls

    /// Drawn, not buttons — see the type comment. `CameraLayout` owns the
    /// geometry and the window hit-tests exactly these rects.
    private var controlBar: some View {
        HStack(spacing: CameraLayout.buttonSpacing) {
            ForEach(Array(CameraLayout.controls(for: state).enumerated()), id: \.offset) { _, action in
                if action == .close {
                    Spacer(minLength: 0)
                    control(action)
                } else {
                    control(action)
                }
            }
        }
        .onAppear { pulse = true }
    }

    @ViewBuilder
    private func control(_ action: CameraAction) -> some View {
        switch action {
        case .openSettings:
            Text("Settings")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: CameraLayout.settingsWidth, height: CameraLayout.buttonSize.height)
                .background(Capsule().fill(DesignTokens.chipFill))
        default:
            Image(systemName: Self.symbol(for: action, state: state))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: CameraLayout.buttonSize.width, height: CameraLayout.buttonSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(action == .toggleMirror && !state.isMirrored
                              ? DesignTokens.hoverHighlight
                              : DesignTokens.chipFill)
                )
        }
    }

    static func symbol(for action: CameraAction, state: CameraState) -> String {
        switch action {
        case .toggleSize: return state.isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        case .switchDevice: return "arrow.triangle.2.circlepath.camera"
        case .toggleMirror: return "flip.horizontal"
        case .close: return "xmark"
        case .openSettings: return "gearshape"
        }
    }
}

/// The streamed NEO preview updates independently of the island layout. A
/// frame no longer asks NotchHub to rebuild the whole notch surface.
///
/// NEO streams the camera's own, unmirrored picture, and its boxes are in
/// that picture's coordinates. Mirrored (the default) flips the picture and
/// the boxes together, so a box stays on the thing it found.
struct NeoCameraStreamPreview: View {
    @ObservedObject var stream: NeoCameraStream
    let mirrored: Bool

    private let frameAspect = 16.0 / 9.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let data = stream.frame, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        // Mirrored the way you expect to see yourself — the
                        // picture only; `detectionBox` flips the boxes to match.
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        .clipped()

                    ForEach(stream.boxes) { box in
                        detectionBox(box, imageSize: image.size, in: geometry.size)
                    }
                } else {
                    RoundedRectangle(cornerRadius: DesignTokens.radiusRow, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay {
                            Image(systemName: "video.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DesignTokens.textTertiary)
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusRow, style: .continuous))
        }
    }

    private func detectionBox(_ box: NeoCameraBox, imageSize: CGSize, in size: CGSize) -> some View {
        let aspect = imageSize.width > 0 && imageSize.height > 0
            ? imageSize.width / imageSize.height : frameAspect
        let drawnWidth = max(size.width, size.height * aspect)
        let drawnHeight = max(size.height, size.width / aspect)
        let cropX = (drawnWidth - size.width) / 2
        let cropY = (drawnHeight - size.height) / 2
        let x = mirrored ? CGFloat(1 - box.x - box.w) : CGFloat(box.x)
        let rect = CGRect(
            x: x * drawnWidth - cropX,
            y: CGFloat(box.y) * drawnHeight - cropY,
            width: CGFloat(box.w) * drawnWidth,
            height: CGFloat(box.h) * drawnHeight
        )
        let accent = Color(red: 0.48, green: 0.91, blue: 0.82)
        let title = box.score > 0 ? "\(box.label) \(Int(box.score * 100))%" : box.label

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(accent.opacity(0.06))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(accent, lineWidth: 1.5)
            if !box.label.isEmpty {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .fixedSize()
                    .offset(x: 2, y: rect.minY < 20 ? 2 : -18)
            }
        }
        .frame(width: max(1, rect.width), height: max(1, rect.height))
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }
}

/// Hosts the capture preview layer.
///
/// The layer belongs to `CameraController` — this view only puts it on screen,
/// so closing the camera can tear the session down without waiting for SwiftUI
/// to let go of anything.
private struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = LayerHostView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.previewLayer = layer
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = view as? LayerHostView else { return }
        if host.previewLayer !== layer {
            host.previewLayer?.removeFromSuperlayer()
            host.previewLayer = layer
            host.layer?.addSublayer(layer)
        }
        host.layoutPreview()
    }

    /// Keeps the preview layer filling the view. A `CALayer` does not
    /// autoresize, so without this the picture stays at its first size while
    /// the island springs around it.
    private final class LayerHostView: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layout() {
            super.layout()
            layoutPreview()
        }

        func layoutPreview() {
            guard let previewLayer else { return }
            // The island's shape is spring-driven, so the layer is resized
            // without an implicit CoreAnimation animation of its own — two
            // animations on the same frame is what reads as lag.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
