import AppKit
import NotchHubCore
import SwiftUI

/// The view that receives island interactions and decides what is clickable.
///
/// This is where the precise hit testing lives: any point outside the island's
/// own frame returns `nil` from `hitTest`, so the click falls through to the
/// window below. The wide transparent envelope around the island therefore
/// never blocks the menu bar or anything else on screen.
final class IslandContainerView: NSView {

    /// The island's frame, in this view's superview (window-base) coordinates.
    var islandFrame: CGRect = .zero {
        didSet {
            guard islandFrame != oldValue else { return }
            updateTrackingArea()
        }
    }

    /// Whether the cursor is currently over the island region. Held so hover
    /// callbacks fire only on real transitions.
    var isMouseInside = false

    /// Whether the island is currently tucked behind the notch. While idle the
    /// surface is coincident with the notch cutout, so it is invisible but
    /// still catches hover (and, on a real notched display, a click) at the
    /// notch itself.
    var isIdle = true

    /// Whether this display really has a notch. When it does not, the idle
    /// region is a synthetic rectangle overlapping the menu bar, so clicks
    /// there must keep falling through.
    var hasNotch = true

    /// Whether the current surface holds real controls (the settings panel).
    /// When it does, clicks are handed to the SwiftUI hosting view so its
    /// toggles work; otherwise the container consumes them as island clicks.
    var needsInteraction = false

    /// A region (window coordinates) whose clicks go to the hosted view even
    /// while the window is NOT key: NEO's panel, which opens on its own as
    /// NEO answers and must take a click on its buttons without first
    /// having stolen the keyboard. The window makes itself key on the first
    /// click inside it (`NotchWindow.sendEvent`).
    var interactiveFrame: CGRect?

    /// The notch itself (window coordinates): where the cursor opens the island
    /// while it is idle.
    var idleNotchFrame: CGRect = .zero

    /// While idle, the pixel pet's own rectangle (window coordinates). It takes
    /// hovers and clicks WITHOUT opening the island; the rest of its black dock
    /// lets the mouse through to whatever is beneath.
    var idlePetFrame: CGRect?

    var onHoverEnter: (() -> Void)?
    /// Every cursor move near the island, in window coordinates (the pet uses
    /// it to notice hovers on itself). Must stay cheap.
    var onMouseMove: ((NSPoint) -> Void)?
    var onHoverExit: (() -> Void)?
    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?
    var rightClickMenu: (() -> NSMenu)?

    /// Hit-tests a point (window coordinates) against the on-screen transport
    /// buttons, returning the command under the cursor or `nil` for a miss.
    /// The island never takes key focus to make these clickable, so the window
    /// routes clicks here first.
    var onTransportHit: ((NSPoint) -> MediaCommand?)?
    /// Hit-tests a point against other on-screen controls (a call's mute /
    /// camera / leave), performing the control and returning `true` on a hit.
    var onControlHit: ((NSPoint) -> Bool)?
    /// Fired when a transport button is actually pressed.
    var onMediaCommand: ((MediaCommand) -> Void)?

    /// A file was dragged over the island / dropped onto it / dragged away.
    var onFileDraggedIn: (() -> Void)?
    var onFileDraggedOut: (() -> Void)?
    var onFileDropped: (([URL]) -> Void)?

    private var trackingArea: NSTrackingArea?

    /// A surface whose every click is its own drawn controls' (NEO's Allow /
    /// Cancel): clicks on it reach `mouseDown` here even while a panel with
    /// real controls holds the window key underneath, and never fall through
    /// to the hosted view.
    var ownsClicks = false

    /// Where the island catches the mouse: its frame as it is NOW in the
    /// model — the final frame of whatever it is springing to, from the
    /// moment the surface is presented (see `IslandHitRegion`).
    var hitRegion: IslandHitRegion {
        IslandHitRegion(islandFrame: islandFrame, idleNotchFrame: idleNotchFrame, idlePetFrame: idlePetFrame, isIdle: isIdle)
    }

    func isOverIdlePet(_ point: NSPoint) -> Bool { hitRegion.isOverIdlePet(point) }

    /// Whether the mouse at `point` belongs to the island (hover or click).
    func catchesMouse(at point: NSPoint) -> Bool { hitRegion.catchesMouse(at: point) }

    /// Whether the cursor at `point` opens the island. Pointing at the resting
    /// pet does not — the pet notices it instead.
    func opensIsland(at point: NSPoint) -> Bool { hitRegion.opensIsland(at: point) }

    /// The island's window is never key while it merely shows something, and
    /// NotchHub is not the active app: without this AppKit would spend the
    /// first click on activating, and a drawn button would need a second one.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Only the island catches the mouse; everything else passes through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = catchesMouse(at: point)
        if !inside {
            if !needsInteraction {
                window?.ignoresMouseEvents = true
            }
            return nil
        }
        // Tucked behind a real notch the island may still be clicked; on a
        // display without one the same region is ordinary menu bar, so let the
        // click through instead of swallowing it.
        if isIdle && !hasNotch { return nil }
        // A surface of drawn controls only (NEO's Allow / Cancel): its clicks
        // are routed by position in `mouseDown`, whatever is underneath.
        if ownsClicks { return self }
        // An interactive surface (settings) must reach its controls, so defer to
        // the normal hit test and let the SwiftUI hosting view handle the click.
        if needsInteraction { return super.hitTest(point) }
        if let interactive = interactiveFrame, interactive.contains(point) { return super.hitTest(point) }
        return self
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        // One stable tracking area covering the whole window. Island hit
        // precision is decided against `islandFrame` on each event instead of
        // by rebuilding the area, because rebuilding it while the cursor is
        // already inside re-fires `mouseEntered` and double-advances the state.
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Recomputes hover against the island's live frame and reports only real
    /// outside→inside / inside→outside transitions.
    private func refreshHover(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMove?(point)
        let inside = opensIsland(at: point)
        if !needsInteraction {
            window?.ignoresMouseEvents = !catchesMouse(at: point)
        }
        guard inside != isMouseInside else { return }
        isMouseInside = inside
        if inside {
            onHoverEnter?()
        } else {
            onHoverExit?()
        }
    }

    /// Called by NotchWindow's global mouse monitor when the mouse moves anywhere
    /// on screen (even over background apps).
    func handleGlobalMouseMove(point: NSPoint, inside: Bool) {
        onMouseMove?(point)
        guard inside != isMouseInside else { return }
        isMouseInside = inside
        if inside {
            onHoverEnter?()
        } else {
            onHoverExit?()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        refreshHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        refreshHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if !needsInteraction {
            window?.ignoresMouseEvents = true
        }
        guard isMouseInside else { return }
        isMouseInside = false
        onHoverExit?()
    }

    // MARK: - Click / right-click

    override func mouseDown(with event: NSEvent) {
        // A click on a transport button is a button press, not an island tap.
        // Route it before the generic click so the user can hit play/pause
        // without the island also cycling its own presentation state.
        let point = convert(event.locationInWindow, from: nil)
        if onControlHit?(point) == true {
            NotchLog.debug("window: control hit at \(point)")
            return
        }
        if let command = onTransportHit?(point) {
            NotchLog.debug("window: transport hit \(command) at \(point)")
            onMediaCommand?(command)
            return
        }
        NotchLog.debug("window: island click at \(point)")
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = rightClickMenu?() else {
            onClick?()
            return
        }
        let notchWindow = window as? NotchWindow
        notchWindow?.setContextMenuTracking(true)
        defer { notchWindow?.setContextMenuTracking(false) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// Esc dismisses an interactive surface (the settings panel), the way it
    /// closes any other macOS panel. Reaches here because the container takes
    /// first responder while a panel with controls is showing.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    // MARK: - Drag & drop (file sharing)

    /// The container is the island's drop target, so the whole notch region
    /// accepts a dragged file — not just the pixels of the surface.
    func registerAsDropTarget() {
        registerForDraggedTypes([.fileURL])
        dropLog("registered file drop target")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        dropLog("draggingEntered urls=\(urls.count)")
        guard !urls.isEmpty else { return [] }
        onFileDraggedIn?()
        return .copy
    }

    /// Verbose-only trace for the drop path, so a failed drag can be told apart
    /// from a drag that never reached the island.
    private func dropLog(_ message: String) {
        guard CommandLine.arguments.contains("--verbose") else { return }
        NotchLog.debug("drop: \(message)")
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropLog("draggingExited")
        onFileDraggedOut?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        dropLog("performDragOperation urls=\(urls.count)")
        guard !urls.isEmpty else { return false }
        onFileDropped?(urls)
        return true
    }

    /// The file URLs carried by a drag, if any.
    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (items as? [URL]) ?? []
    }
}

/// The hosting view for the island's SwiftUI content: one that takes the
/// first click, like the container it sits in (see
/// `IslandContainerView.acceptsFirstMouse`) — a panel's real controls must not
/// need one click to wake the window and another to act.
final class IslandHostingView: NSHostingView<IslandRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The borderless, transparent window that hosts the island.
///
/// It sits above the menu bar, has no chrome of its own, and is sized to the
/// island's current shape. Its content view owns hit testing, so the island is
/// precisely clickable while the surrounding transparent area is not.
final class NotchWindow: NSPanel {

    private var geometry: NotchGeometry
    private let container = IslandContainerView()

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isContextMenuTracking = false
    var onContextMenuTrackingChanged: ((Bool) -> Void)?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        // NSPanel's own default, read before anything can change it.
        self.defaultSharingType = .readWrite
        let frame = geometry.compactFrame
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // A non-activating panel never takes key/main status on its own, so it
        // can hover and show the island without stealing focus from the user's
        // app. It is the correct window type for an always-on-top overlay that
        // must let clicks pass through to everything beneath it.
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        // The island is drawn entirely by SwiftUI; AppKit must not paint a titlebar.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false

        contentView = container

        // The island doubles as a drop target for file sharing.
        container.registerAsDropTarget()

        // Monitor mouse movement to wake up the window when the cursor enters
        // the island region. We need both a local monitor (for when NotchHub
        // is active) and a global monitor (for when the user is in Chrome/other
        // apps).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self else { return event }
            // Window-local only when the event's window is this one. With no
            // window at all — the cursor outside the island while NotchHub is
            // the active app, as it is after a panel closes — the location is
            // in screen coordinates, and read as local it once opened the
            // wings with the mouse far away. See `MouseLocation`.
            self.handleMouseMove(MouseLocation.inWindow(event.locationInWindow, eventWindowFrame: event.window?.frame, windowFrame: self.frame))
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            // Global events are in screen coordinates.
            self?.handleMouseMove(event.locationInWindow, isScreen: true)
        }
    }

    deinit {
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
    }

    private var lastMousePoint: NSPoint = .zero

    private func handleMouseMove(_ location: NSPoint, isScreen: Bool = false) {
        // NSMenu owns pointer tracking while its context menu is open. Avoid
        // running hover hit tests and pet reactions for those same events.
        guard !isContextMenuTracking else { return }
        guard !needsInteraction else {
            ignoresMouseEvents = false
            return
        }
        
        let point: NSPoint
        if isScreen {
            // Convert screen (bottom-left) to window-local (bottom-left).
            point = NSPoint(x: location.x - frame.minX, y: location.y - frame.minY)
        } else {
            point = location
        }

        // Only process if the mouse actually moved.
        guard point != lastMousePoint else { return }
        lastMousePoint = point

        let catches = container.catchesMouse(at: point)
        let inside = container.opensIsland(at: point)
        if catches != !ignoresMouseEvents {
            ignoresMouseEvents = !catches
            // Only log when the state changes to keep the log clean.
            log("mouse=\(point.x),\(point.y) inside=\(inside) ignoresMouseEvents=\(ignoresMouseEvents)")
        }

        // Forward to the container so onHoverEnter / onHoverExit fire even when
        // the mouse moved while another application was frontmost.
        container.handleGlobalMouseMove(point: point, inside: inside)
        // A render that move triggered (the pet caught, a panel opened) may have
        // reset capture: settle it for where the cursor is.
        if !needsInteraction {
            ignoresMouseEvents = !container.catchesMouse(at: point)
        }
    }

    func setContextMenuTracking(_ tracking: Bool) {
        guard tracking != isContextMenuTracking else { return }
        isContextMenuTracking = tracking
        onContextMenuTrackingChanged?(tracking)
    }

    private func log(_ message: String) {
        // We use the same verbose flag as the app.
        if CommandLine.arguments.contains("--verbose") {
            NotchLog.debug("\(message)")
        }
    }

    override var canBecomeKey: Bool { needsInteraction || quietKey }
    override var canBecomeMain: Bool { needsInteraction || quietKey }

    // MARK: - Quiet keys (Search Screen's card in NEO's panel)

    /// The panel has the keyboard WITHOUT NotchHub having been activated: the
    /// user's app stays the active one (its menu bar, its full-screen Space),
    /// and the window — a non-activating panel — takes the keys only. Used for
    /// Search Screen's card, which opens on its own as an area flies into the
    /// notch: Esc, a click elsewhere (another window becoming key) or an action
    /// that opens something folds it. Every other panel keeps
    /// `needsInteraction`, which activates NotchHub on a click.
    private(set) var quietKey = false

    /// The window lost the keys it took quietly (a click elsewhere made
    /// another window key).
    var onQuietKeyLost: (() -> Void)?

    /// Takes the keyboard for `responder` quietly: no app activation, no
    /// change of level.
    func takeKeysQuietly(_ responder: NSResponder) {
        quietKey = true
        makeKey()
        makeFirstResponder(responder)
    }

    /// Gives back keys taken quietly (the panel folded): nothing is told.
    ///
    /// `resignKey()` is only AppKit's notice that key status went — called
    /// directly it moves nothing, and the island would stay the key window
    /// (the user's typing landing here). Ordering the window out is what ends
    /// a non-activating panel's key status: the window server hands the
    /// keyboard back to the active app — the user's, as NotchHub was never
    /// activated for these keys — and the island comes straight back, never
    /// key (`orderFrontRegardless`).
    func releaseQuietKeys() {
        guard quietKey else { return }
        quietKey = false
        guard isKeyWindow else { return }
        makeFirstResponder(container) // (no key in between reaches the page)
        orderOut(nil)
        orderFrontRegardless()
    }

    override func resignKey() {
        super.resignKey()
        guard quietKey else { return }
        quietKey = false
        onQuietKeyLost?()
    }

    /// With the keys taken quietly there is no menu of NotchHub's to route
    /// the editing keys through (an accessory app's). The page sees every key
    /// first — WebKit takes a ⌘-key through the view hierarchy's
    /// `performKeyEquivalent` (that is how NEO's card hears ⌘C) and sends back
    /// the ones its page left alone — and only one nobody took goes to the
    /// first responder (the question box) as the edit action.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        Self.routeKeyEquivalent(
            event,
            quiet: quietKey,
            page: { super.performKeyEquivalent(with: event) },
            send: { NSApp.sendAction($0, to: nil, from: self) }
        )
    }

    /// The order of `performKeyEquivalent`: the window's views (the page)
    /// first; then, with the keys taken quietly, an editing key nobody took
    /// as its edit action. Returns whether the key was taken.
    static func routeKeyEquivalent(
        _ event: NSEvent, quiet: Bool, page: () -> Bool, send: (Selector) -> Bool
    ) -> Bool {
        if page() { return true }
        guard quiet, event.type == .keyDown, let action = editingAction(for: event) else { return false }
        return send(action)
    }

    /// ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z and ⇧⌘Z, as the actions an Edit menu would send.
    static func editingAction(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return nil }
        let shift = flags.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c" where !shift: return #selector(NSText.copy(_:))
        case "x" where !shift: return #selector(NSText.cut(_:))
        case "v" where !shift: return #selector(NSText.paste(_:))
        case "a" where !shift: return #selector(NSText.selectAll(_:))
        case "z": return shift ? Selector(("redo:")) : Selector(("undo:"))
        default: return nil
        }
    }

    /// Fired as the window takes key status for a click inside
    /// `interactiveFrame`, before the click is delivered.
    var onInteractiveClick: (() -> Void)?

    /// A key went down while the window is key: (key code, is an auto-repeat).
    /// Returns whether it was taken (it then goes no further).
    var onKeyDown: ((UInt16, Bool) -> Bool)?

    /// A click inside the interactive region of a non-key window (NEO's
    /// panel, opened on its own) makes the window key first — the app
    /// activates and the panel can take typing — then the click lands on
    /// whatever was clicked, so the first click is never swallowed.
    override func sendEvent(_ event: NSEvent) {
        // (With the keys taken quietly the window is key already: a click on
        // the panel must not activate NotchHub.)
        if event.type == .leftMouseDown, !needsInteraction, !quietKey,
           let interactive = container.interactiveFrame, interactive.contains(event.locationInWindow) {
            needsInteraction = true
            onInteractiveClick?()
        }
        // NEO's Allow / Cancel take Return and Esc while they have the
        // keyboard (the window is key): before any panel underneath does.
        if event.type == .keyDown, onKeyDown?(event.keyCode, event.isARepeat) == true {
            return
        }
        // Esc with NEO's panel open closes it, as it closes any panel. The
        // web view is first responder then and keeps the key to itself, so
        // the container's `cancelOperation` never heard it: the page sees
        // it first (a question on its card answers "no" to Esc), then the
        // panel folds.
        if event.type == .keyDown, event.keyCode == 53, container.interactiveFrame != nil {
            super.sendEvent(event)
            onCancel?()
            return
        }
        super.sendEvent(event)
    }

    /// Whether the window may take key/main status to receive control clicks.
    ///
    /// The hover/click island must never steal focus from the user's app, so it
    /// stays non-key by default. But the settings panel holds real controls
    /// (SwiftUI toggles) that need a key window to accept clicks, so it flips
    /// this on while an interactive panel is showing.
    var needsInteraction = false {
        didSet {
            guard needsInteraction != oldValue else { return }
            container.needsInteraction = needsInteraction
            if needsInteraction {
                ignoresMouseEvents = false
                // An accessory (LSUIElement) app's window only becomes key once
                // the app itself is active, so activate before ordering front.
                // Lowering the level off the menu-bar strip is required for the
                // window to receive control clicks.
                level = .floating
                NSApp.activate(ignoringOtherApps: true)
                makeKeyAndOrderFront(nil)
                // Esc must reach the container's `cancelOperation`.
                makeFirstResponder(container)
            } else {
                ignoresMouseEvents = !container.isMouseInside
                level = .statusBar
                if isKeyWindow {
                    // The island must never hold focus once its controls are
                    // gone, or the user's typing would keep landing here.
                    resignKey()
                }
            }
        }
    }

    // MARK: - Interaction (forwarded to the container view)

    var onHoverEnter: (() -> Void)? {
        get { container.onHoverEnter }
        set { container.onHoverEnter = newValue }
    }
    var onHoverExit: (() -> Void)? {
        get { container.onHoverExit }
        set { container.onHoverExit = newValue }
    }
    var onMouseMove: ((NSPoint) -> Void)? {
        get { container.onMouseMove }
        set { container.onMouseMove = newValue }
    }
    /// See `IslandContainerView.idlePetFrame`.
    var idlePetFrame: CGRect? {
        get { container.idlePetFrame }
        set {
            guard newValue != container.idlePetFrame else { return }
            container.idlePetFrame = newValue
            syncMouseCapture()
        }
    }
    var onClick: (() -> Void)? {
        get { container.onClick }
        set { container.onClick = newValue }
    }
    var onTransportHit: ((NSPoint) -> MediaCommand?)? {
        get { container.onTransportHit }
        set { container.onTransportHit = newValue }
    }
    var onControlHit: ((NSPoint) -> Bool)? {
        get { container.onControlHit }
        set { container.onControlHit = newValue }
    }
    var onMediaCommand: ((MediaCommand) -> Void)? {
        get { container.onMediaCommand }
        set { container.onMediaCommand = newValue }
    }
    var onCancel: (() -> Void)? {
        get { container.onCancel }
        set { container.onCancel = newValue }
    }

    /// A file was dragged over the island / dragged away / dropped onto it.
    var onFileDraggedIn: (() -> Void)? {
        get { container.onFileDraggedIn }
        set { container.onFileDraggedIn = newValue }
    }
    var onFileDraggedOut: (() -> Void)? {
        get { container.onFileDraggedOut }
        set { container.onFileDraggedOut = newValue }
    }
    var onFileDropped: (([URL]) -> Void)? {
        get { container.onFileDropped }
        set { container.onFileDropped = newValue }
    }
    var rightClickMenu: (() -> NSMenu)? {
        get { container.rightClickMenu }
        set { container.rightClickMenu = newValue }
    }

    /// Whether the island's own view takes the first click in a window that
    /// is not key — for the self-test.
    var acceptsFirstClick: Bool { container.acceptsFirstMouse(for: nil) }

    /// Installs the SwiftUI island as a subview filling the container.
    func installContent(_ view: NSView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    /// The notch's height — the strip of every island shape that the notch
    /// itself hides from view.
    var notchHeight: CGFloat { geometry.notchFrame.height }

    /// The notch's width — the gap the wings leave in the middle of the bar.
    var notchWidth: CGFloat { geometry.notchFrame.width }

    /// The display's size, for surfaces sized against it.
    var screenSize: CGSize { geometry.screenFrame.size }

    /// Re-reads the display geometry (call on screen-parameter changes).
    func refreshGeometry() {
        geometry = NotchGeometry.detectMain()
    }

    /// Sizes the window once, to the largest surface the island can become,
    /// then only reports where the island sits inside it.
    ///
    /// The window is deliberately never resized per state: AppKit changes a
    /// window's frame instantly, so resizing on hover would visibly snap the
    /// island while its SwiftUI content tried to animate. A fixed envelope
    /// leaves the whole transition to SwiftUI, which is what makes it smooth.
    /// It costs nothing because `hitTest` already passes clicks through
    /// anywhere outside the island's own frame.
    ///
    /// While idle the island is invisible, but the window still accepts hover
    /// over the notch region so the island can be summoned by the cursor.
    func apply(state: IslandState, content: IslandContentSize = .default) {
        let envelope = geometry.envelopeFrame.insetBy(dx: -Self.shadowMargin, dy: -Self.shadowMargin)
        if frame != envelope {
            setFrame(envelope, display: false)
        }
        container.islandFrame = localFrame(for: state, content: content)
        // NEO's panel takes clicks without being key (see `interactiveFrame`).
        container.interactiveFrame = state == .neoPanel ? container.islandFrame : nil
        // NEO's Allow / Cancel are drawn controls, and every click on them is theirs.
        container.ownsClicks = state == .neoConfirm
        container.idleNotchFrame = localFrame(for: .idle, content: .default)
        container.isIdle = (state == .idle)
        container.hasNotch = geometry.hasNotch
        container.needsInteraction = needsInteraction
        // The window tracks hover; mouse events pass through to windows beneath
        // unless the cursor is over the island (or the resting pet) or an
        // interactive panel is open.
        syncMouseCapture()
    }

    /// Re-derives mouse capture from where the cursor is now — after a change of
    /// shape or pet the cursor did not move for.
    ///
    /// From the cursor's real position against the island's new frame, not
    /// from the last hover the window heard of: a surface that comes up under
    /// a still cursor (NEO's Allow / Cancel, its panel) was otherwise "not
    /// hovered", the window went on ignoring the mouse, and the first click —
    /// made without moving the mouse — went to the app underneath.
    func syncMouseCapture() {
        let screen = NSEvent.mouseLocation
        let point = NSPoint(x: screen.x - frame.minX, y: screen.y - frame.minY)
        ignoresMouseEvents = container.hitRegion.windowIgnoresMouse(cursorAt: point, interactive: needsInteraction)
            && !container.isMouseInside
    }

    /// Whether a click at `point` (window coordinates) would reach the island
    /// right now — for the self-test.
    func takesClick(at point: NSPoint) -> Bool {
        container.hitTest(point) != nil
    }

    /// A panel opened by clicking the resting pet: the cursor is already on it.
    /// Adopt that hover without telling anyone (the machine stays idle), so
    /// leaving the panel — however fast — closes it.
    func adoptHover() {
        let screen = NSEvent.mouseLocation
        let point = NSPoint(x: screen.x - frame.minX, y: screen.y - frame.minY)
        lastMousePoint = point
        guard container.opensIsland(at: point) else { return }
        container.isMouseInside = true
        if !needsInteraction {
            ignoresMouseEvents = false
        }
    }

    /// The window must be free to sit above the menu bar: the island hangs from
    /// the very top of the display, and the top of every panel is the notch
    /// strip. AppKit's default constraint clamps a window to the screen's
    /// *visible* frame, which silently truncated the island's top (and pushed
    /// its SwiftUI frame to a negative origin, breaking hit testing).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Uniform margin around the island so its shadow is never clipped.
    static let shadowMargin: CGFloat = 24

    // MARK: - Ghost Mode

    /// Whether the island is hidden from screen capture.
    ///
    /// `NSWindow.sharingType = .none` takes the window out of every capture
    /// path macOS has — screen sharing in a call, QuickTime and Screenshot
    /// recordings, ⇧⌘3/4/5, and anything built on ScreenCaptureKit — while
    /// leaving it on the physical display. It is the OS doing the hiding, not
    /// the app drawing something different, so there is no frame where the
    /// island leaks into a recording.
    var hidesFromCapture: Bool = false {
        didSet {
            guard hidesFromCapture != oldValue else { return }
            // Restore whatever the window had rather than assuming a value:
            // turning Ghost Mode off must put the window back exactly as it
            // was, not merely somewhere capturable.
            sharingType = hidesFromCapture ? .none : defaultSharingType
            log("ghost: hidesFromCapture=\(hidesFromCapture)")
        }
    }

    /// The window's sharing type before Ghost Mode ever touched it.
    ///
    /// Captured in `init`, NOT lazily: a lazy property is evaluated on first
    /// READ, which is inside the `didSet` that turns Ghost Mode back OFF — by
    /// which point `sharingType` is already `.none`, so it would restore the
    /// hidden value and the island never came back into capture.
    private let defaultSharingType: NSWindow.SharingType

    /// The island's frame in window-local AppKit coordinates (bottom-left
    /// origin). The container's hit testing lives in this space.
    func localFrame(for state: IslandState, content: IslandContentSize = .default) -> CGRect {
        let target = geometry.frame(for: state, content: content)
        let origin = frame.origin
        return CGRect(
            x: target.minX - origin.x,
            y: target.minY - origin.y,
            width: target.width,
            height: target.height
        )
    }

    /// The island's frame in the SwiftUI view's coordinate space.
    ///
    /// SwiftUI lays out from the TOP-LEFT; AppKit from the BOTTOM-LEFT. While
    /// the window was a snug box around the island the two agreed by
    /// coincidence, but now that it is a fixed envelope the difference is
    /// hundreds of points — without this flip the island renders far down the
    /// screen instead of hanging from the notch.
    func swiftUIFrame(for state: IslandState, content: IslandContentSize = .default) -> CGRect {
        let appKit = localFrame(for: state, content: content)
        return CGRect(
            x: appKit.minX,
            y: frame.height - appKit.maxY,
            width: appKit.width,
            height: appKit.height
        )
    }

    /// Whether the cursor is over the island right now.
    var isMouseOverIsland: Bool { container.isMouseInside }

    var cornerRadius: CGFloat { geometry.cornerRadius }
    var hasNotch: Bool { geometry.hasNotch }
}
