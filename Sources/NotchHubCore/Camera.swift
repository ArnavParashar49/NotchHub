import CoreGraphics
import Foundation

/// Why the camera cannot show a picture.
public enum CameraFailure: Equatable, Sendable {
    /// macOS has been told to refuse the camera.
    case permissionDenied
    /// Nothing to show a picture from.
    case noDevice
    /// The capture session refused to start, or dropped out.
    case unavailable(String)

    public var message: String {
        switch self {
        case .permissionDenied: return "Camera access is off"
        case .noDevice: return "No camera found"
        case let .unavailable(reason): return reason
        }
    }

    public var detail: String {
        switch self {
        case .permissionDenied: return "Grant it in System Settings"
        case .noDevice: return "Connect one and try again"
        case .unavailable: return "Try closing other apps using it"
        }
    }

    /// Whether the island should offer the settings link.
    public var isPermission: Bool { self == .permissionDenied }
}

/// One camera the Mac can show.
public struct CameraDevice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Where the camera preview has got to.
public enum CameraPhase: Equatable, Sendable {
    case idle
    /// Asking for permission and opening the device.
    case starting
    /// A picture is on screen.
    case live
    case failed(CameraFailure)

    /// Whether the capture session is, or is about to be, running. This is what
    /// "is the camera on?" is decided from — never the panel being open.
    public var isRunning: Bool {
        switch self {
        case .starting, .live: return true
        case .idle, .failed: return false
        }
    }

    /// Whether the island should be showing the camera surface.
    public var isPresented: Bool { self != .idle }
}

/// The camera preview's state.
public struct CameraState: Equatable, Sendable {
    public var phase: CameraPhase
    /// Every camera the Mac can offer, for the switch control.
    public var devices: [CameraDevice]
    /// The one being shown.
    public var deviceID: String?
    /// Whether the preview is in its larger shape.
    public var isExpanded: Bool
    /// Mirrored, the way you expect to see yourself. Front cameras only look
    /// right this way; it never affects what anything else records.
    public var isMirrored: Bool

    public init(
        phase: CameraPhase = .idle,
        devices: [CameraDevice] = [],
        deviceID: String? = nil,
        isExpanded: Bool = false,
        isMirrored: Bool = true
    ) {
        self.phase = phase
        self.devices = devices
        self.deviceID = deviceID
        self.isExpanded = isExpanded
        self.isMirrored = isMirrored
    }

    public var isRunning: Bool { phase.isRunning }
    public var isPresented: Bool { phase.isPresented }

    /// The camera being shown, when it is known.
    public var device: CameraDevice? {
        devices.first { $0.id == deviceID }
    }

    /// Whether there is more than one camera to switch between.
    public var canSwitchDevice: Bool { devices.count > 1 }

    /// The camera after the current one, wrapping around.
    public var nextDeviceID: String? {
        guard devices.count > 1 else { return nil }
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return devices.first?.id }
        return devices[(index + 1) % devices.count].id
    }

    /// The headline the island shows.
    public var statusText: String {
        switch phase {
        case .idle: return "Camera"
        case .starting: return "Starting camera…"
        case .live: return device?.name ?? "Camera"
        case let .failed(failure): return failure.message
        }
    }

    /// The quiet second line.
    public var detailText: String {
        switch phase {
        case .idle, .starting: return "One moment"
        case .live: return canSwitchDevice ? "\(devices.count) cameras" : "Live"
        case let .failed(failure): return failure.detail
        }
    }
}

// MARK: - Layout

/// Something the camera preview does when clicked.
public enum CameraAction: Equatable, Sendable {
    /// Between the small and larger previews.
    case toggleSize
    /// To the next camera the Mac has.
    case switchDevice
    /// Flip the picture left to right.
    case toggleMirror
    case close
    /// Open System Settings at the camera pane.
    case openSettings
}

/// The geometry of the camera preview's clickable areas.
///
/// Drawn controls hit-tested by the window, for the same reason as everywhere
/// else in the island: checking your hair before a call must not pull focus out
/// of the app you are about to present from.
public enum CameraLayout {
    public static let horizontalInset: CGFloat = 10
    /// The control bar below the picture, and the gap above it.
    public static let barHeight: CGFloat = 28
    public static let barBottomInset: CGFloat = 8
    public static let pictureBottomGap: CGFloat = 6
    public static let buttonSize = CGSize(width: 28, height: 24)
    public static let buttonSpacing: CGFloat = 4

    /// Everything the panel needs below the picture: the gap, the bar and the
    /// bar's own bottom inset. `NotchGeometry` sizes the panel from this plus
    /// the picture's 16:9 height.
    public static var chromeHeight: CGFloat {
        pictureBottomGap + barHeight + barBottomInset
    }

    /// The picture: full width inside the insets, directly below the notch
    /// strip, 16:9.
    public static func pictureFrame(in frame: CGRect, notchInset: CGFloat) -> CGRect {
        let top = frame.maxY - notchInset
        let bottom = frame.minY + barBottomInset + barHeight + pictureBottomGap
        return CGRect(
            x: frame.minX + horizontalInset,
            y: bottom,
            width: frame.width - horizontalInset * 2,
            height: max(0, top - bottom)
        )
    }

    /// The controls a state offers, left to right. A failed camera offers only
    /// the remedy and a way out; a live one offers the full set.
    public static func controls(for state: CameraState) -> [CameraAction] {
        switch state.phase {
        case let .failed(failure):
            return failure.isPermission ? [.openSettings, .close] : [.close]
        case .idle, .starting:
            return [.close]
        case .live:
            var actions: [CameraAction] = [.toggleSize, .toggleMirror]
            if state.canSwitchDevice { actions.append(.switchDevice) }
            actions.append(.close)
            return actions
        }
    }

    /// Every clickable area, in AppKit coordinates. Close sits on its own at the
    /// trailing end; everything else runs from the leading edge.
    public static func actions(in frame: CGRect, state: CameraState) -> [(action: CameraAction, rect: CGRect)] {
        let all = controls(for: state)
        let y = frame.minY + barBottomInset + (barHeight - buttonSize.height) / 2
        var result: [(action: CameraAction, rect: CGRect)] = []

        if all.contains(.close) {
            result.append((.close, CGRect(
                x: frame.maxX - horizontalInset - buttonSize.width,
                y: y,
                width: buttonSize.width,
                height: buttonSize.height
            )))
        }

        var x = frame.minX + horizontalInset
        for action in all where action != .close {
            // The settings remedy is a labelled chip, not a glyph button.
            let width = action == .openSettings ? settingsWidth : buttonSize.width
            result.append((action, CGRect(x: x, y: y, width: width, height: buttonSize.height)))
            x += width + buttonSpacing
        }
        return result
    }

    /// The width of the "Settings" chip a refused camera offers.
    public static let settingsWidth: CGFloat = 70

    /// The action under a point, or `nil` for a miss.
    public static func action(at point: CGPoint, in frame: CGRect, state: CameraState) -> CameraAction? {
        actions(in: frame, state: state)
            .first { $0.rect.insetBy(dx: -2, dy: -4).contains(point) }?
            .action
    }

    /// The System Settings pane that grants camera access.
    public static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
}
