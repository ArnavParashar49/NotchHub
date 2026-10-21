import Foundation

/// The display NotchHub's island is on (its `NSScreenNumber`, a
/// CGDirectDisplayID), as the app last set it — read by `NeoListener` on its
/// own queue for `lens_card_hello`, so NEO's Search Screen flies an area to
/// the notch on the right display (or lifts it where it is, on another).
public enum NeoIslandDisplay {
    private static let lock = NSLock()
    private static var stored: UInt32?

    public static var current: UInt32? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public static func set(_ display: UInt32?) {
        lock.lock()
        stored = display
        lock.unlock()
    }
}
