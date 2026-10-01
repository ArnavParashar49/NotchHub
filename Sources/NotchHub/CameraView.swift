import AppKit
import AVFoundation
import NotchHubCore
import SwiftUI

/// The camera preview: the picture, and a quiet bar of controls under it.
///
/// The picture is a real `AVCaptureVideoPreviewLayer` hosted in an `NSView` —
/// there is no frame capture anywhere in the path, so the preview cannot record
/// even in principle. The controls are DRAWN and hit-tested by the window, like
/// every other island surface, so checking your hair before a call never pulls
/// focus out of the app you are about to present from.
struct CameraView: View {
    let state: CameraState
    /// The live preview layer, when there is one.
    let previewLayer: AVCaptureVideoPreviewLayer?

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

            if state.phase == .live, let previewLayer {
                CameraPreview(layer: previewLayer)
                    // Mirrored the way you expect to see yourself. This flips
                    // the PREVIEW only; nothing is being captured to flip.
                    .scaleEffect(x: state.isMirrored ? -1 : 1, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusRow, style: .continuous))
                    .transition(.opacity)
            } else {
                placeholder
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
