import CoreGraphics

// MARK: - Browser actions

/// Something the island can do to the frontmost browser.
public enum BrowserAction: Equatable, Sendable {
    case back
    case forward
    case reload
    case newTab
    /// Switch the front window to this tab (1-based).
    case selectTab(Int)

    /// The browser's own shortcut for the action, sent as a keystroke — every
    /// browser (Safari, Chrome, Arc, Comet, Firefox…) answers to these. Tab
    /// selection has none; it goes through scripting.
    public var shortcut: KeyChord? {
        switch self {
        case .back: return KeyChord(keyCode: KeyChord.Key.leftBracket)
        case .forward: return KeyChord(keyCode: KeyChord.Key.rightBracket)
        case .reload: return KeyChord(keyCode: KeyChord.Key.r)
        case .newTab: return KeyChord(keyCode: KeyChord.Key.t)
        case .selectTab: return nil
        }
    }
}

public extension KeyChord.Key {
    static let leftBracket: UInt16 = 0x21
    static let rightBracket: UInt16 = 0x1E
    static let r: UInt16 = 0x0F
    static let t: UInt16 = 0x11
}

// MARK: - Hover strip

/// The browser controls on the right wing of the hover strip. `WingView` draws
/// them from these numbers and the window hit-tests against them.
public enum WingControlLayout {
    public static let buttonSize: CGFloat = 22
    public static let spacing: CGFloat = 6
    public static let controls: [BrowserAction] = [.back, .forward, .newTab]

    public static var controlsWidth: CGFloat {
        buttonSize * CGFloat(controls.count) + spacing * CGFloat(controls.count - 1)
    }

    /// Button rects for a wings frame in AppKit coordinates: flush with the
    /// right wing's trailing edge (`inset` in), and never under the notch.
    /// `trailingReserve` is room kept free beyond the buttons (the pixel pet);
    /// it moves the buttons in from the edge but never into the notch.
    public static func browserButtons(in frame: CGRect, notchWidth: CGFloat, inset: CGFloat, trailingReserve: CGFloat = 0) -> [(action: BrowserAction, rect: CGRect)] {
        let x0 = max(frame.maxX - inset - trailingReserve - controlsWidth, frame.midX + notchWidth / 2 + inset)
        let y = frame.midY - buttonSize / 2
        return controls.enumerated().map { i, action in
            (action, CGRect(x: x0 + CGFloat(i) * (buttonSize + spacing), y: y, width: buttonSize, height: buttonSize))
        }
    }

    public static func browserAction(at point: CGPoint, in frame: CGRect, notchWidth: CGFloat, inset: CGFloat, trailingReserve: CGFloat = 0) -> BrowserAction? {
        browserButtons(in: frame, notchWidth: notchWidth, inset: inset, trailingReserve: trailingReserve)
            .first { $0.rect.insetBy(dx: -2, dy: -3).contains(point) }?
            .action
    }
}

// MARK: - App panel

/// Something an app panel does when clicked.
public enum AppPanelAction: Equatable, Sendable {
    /// Switch to the dashboard (the clock in the notch strip).
    case dashboard
    /// Open settings ("···").
    case settings
    case browser(BrowserAction)
}

/// The geometry of an app panel's clickable areas, shared by the views and the
/// window's hit test.
public enum AppPanelLayout {
    public static let horizontalInset: CGFloat = 20
    public static let topInset: CGFloat = 12
    public static let bottomInset: CGFloat = 14
    public static let headerHeight: CGFloat = 32
    public static let sectionGap: CGFloat = 10

    /// Notch-strip controls: the clock (→ dashboard) left, "···" right.
    public static let clockSize = CGSize(width: 56, height: 22)
    public static let moreSize = CGSize(width: 32, height: 22)

    // Browser
    public static let maxTabCards = 3
    public static let tabCardHeight: CGFloat = 52
    public static let tabCardSpacing: CGFloat = 8
    public static let controlRowHeight: CGFloat = 26
    public static let newTabWidth: CGFloat = 86
    public static let iconButtonSize: CGFloat = 26
    public static let iconButtonSpacing: CGFloat = 8

    /// Width of one tab-card slot. Slots are fixed so cards never shift.
    public static func tabCardWidth(panelWidth: CGFloat) -> CGFloat {
        let slots = CGFloat(maxTabCards)
        return (panelWidth - horizontalInset * 2 - tabCardSpacing * (slots - 1)) / slots
    }

    /// Every clickable area for a panel frame in AppKit coordinates.
    /// `browserTabs` is the tab row for a browser panel, `nil` for others.
    public static func actions(in frame: CGRect, notchInset: CGFloat, browserTabs: [BrowserTab]?) -> [(action: AppPanelAction, rect: CGRect)] {
        let stripMidY = frame.maxY - notchInset / 2
        var result: [(action: AppPanelAction, rect: CGRect)] = [
            (.dashboard, CGRect(x: frame.minX + horizontalInset, y: stripMidY - clockSize.height / 2, width: clockSize.width, height: clockSize.height)),
            (.settings, CGRect(x: frame.maxX - horizontalInset - moreSize.width, y: stripMidY - moreSize.height / 2, width: moreSize.width, height: moreSize.height)),
        ]
        guard let browserTabs else { return result }

        let cardTop = frame.maxY - notchInset - topInset - headerHeight - sectionGap
        let cardWidth = tabCardWidth(panelWidth: frame.width)
        for (slot, tab) in browserTabs.prefix(maxTabCards).enumerated() {
            let x = frame.minX + horizontalInset + CGFloat(slot) * (cardWidth + tabCardSpacing)
            result.append((.browser(.selectTab(tab.index)), CGRect(x: x, y: cardTop - tabCardHeight, width: cardWidth, height: tabCardHeight)))
        }

        let rowY = frame.minY + bottomInset
        result.append((.browser(.newTab), CGRect(x: frame.minX + horizontalInset, y: rowY, width: newTabWidth, height: controlRowHeight)))
        let reload = CGRect(x: frame.maxX - horizontalInset - iconButtonSize, y: rowY, width: iconButtonSize, height: controlRowHeight)
        let forward = reload.offsetBy(dx: -(iconButtonSize + iconButtonSpacing), dy: 0)
        let back = forward.offsetBy(dx: -(iconButtonSize + iconButtonSpacing), dy: 0)
        result.append((.browser(.back), back))
        result.append((.browser(.forward), forward))
        result.append((.browser(.reload), reload))
        return result
    }

    public static func action(at point: CGPoint, in frame: CGRect, notchInset: CGFloat, browserTabs: [BrowserTab]?) -> AppPanelAction? {
        actions(in: frame, notchInset: notchInset, browserTabs: browserTabs)
            .first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }?
            .action
    }
}

// MARK: - Meeting strip

public extension MeetingControlLayout {
    /// The mute / leave buttons on the trailing end of a call's compact bar.
    static let compactButtonSize: CGFloat = 22
    static let compactButtonSpacing: CGFloat = 8
    static var compactControlsWidth: CGFloat { compactButtonSize * 2 + compactButtonSpacing }

    static func compactButtons(in frame: CGRect, inset: CGFloat) -> [(control: MeetingControl, rect: CGRect)] {
        let y = frame.midY - compactButtonSize / 2
        let leave = CGRect(x: frame.maxX - inset - compactButtonSize, y: y, width: compactButtonSize, height: compactButtonSize)
        let mute = leave.offsetBy(dx: -(compactButtonSize + compactButtonSpacing), dy: 0)
        return [(.mute, mute), (.leave, leave)]
    }

    static func compactControl(at point: CGPoint, in frame: CGRect, inset: CGFloat) -> MeetingControl? {
        compactButtons(in: frame, inset: inset)
            .first { $0.rect.insetBy(dx: -2, dy: -3).contains(point) }?
            .control
    }
}
