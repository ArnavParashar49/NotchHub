import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey.
///
/// Carbon's `RegisterEventHotKey` is the only global shortcut that needs no
/// Accessibility permission, which matters here: dictation and the Tray must
/// work on a fresh install before the user has granted anything.
final class HotKey {

    private var reference: EventHotKeyRef?
    private let handler: () -> Void
    private let identifier: UInt32

    /// Live hotkeys, keyed by Carbon's own id, so the C callback can find them.
    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    /// Modifier masks, mirroring the Carbon constants.
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    /// Registers a hotkey. `keyCode` is a virtual key code (see `Key`).
    init?(keyCode: UInt32, modifiers: Modifiers, handler: @escaping () -> Void) {
        self.handler = handler
        self.identifier = HotKey.nextID
        HotKey.nextID += 1

        HotKey.installHandlerIfNeeded()

        let eventID = EventHotKeyID(signature: OSType(0x4E4F5443), id: identifier) // 'NOTC'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            eventID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return nil }
        self.reference = ref
        HotKey.registry[identifier] = self
        _ = eventID
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        HotKey.registry[identifier] = nil
    }

    /// Virtual key codes for the letters the app uses.
    enum Key {
        static let m: UInt32 = UInt32(kVK_ANSI_M)
        static let v: UInt32 = UInt32(kVK_ANSI_V)
        static let t: UInt32 = UInt32(kVK_ANSI_T)
        static let comma: UInt32 = UInt32(kVK_ANSI_Comma)
    }

    // MARK: - Carbon plumbing

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, let hotKey = HotKey.registry[hotKeyID.id] else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { hotKey.handler() }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
