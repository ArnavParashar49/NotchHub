import AppKit
import NotchHubCore
import UserNotifications

/// Observes notifications delivered to the user and surfaces them on the island.
///
/// Honest scope: macOS does not expose OTHER apps' notification banners to
/// third-party apps through public APIs. `UNUserNotificationCenter` only
/// delivers notifications that belong to this app. So this listener surfaces
/// notifications routed to NotchHub itself (e.g. its own timer/download
/// completions), which is the only case the public API can see.
///
/// Mirroring every app's banners would require Full Disk Access and parsing
/// Apple's private `usernoted` database — a fragile hack the spec explicitly
/// forbids ("never fake unavailable system information"). We deliberately do
/// not do that; the toggle gates a listener that does real, bounded work rather
/// than pretending to see the whole system.
public final class NotificationListener: NSObject, SystemListener, UNUserNotificationCenterDelegate {

    private let emit: (SystemEvent) -> Void

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
        super.init()
    }

    public var name: String { "Notifications" }

    public func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Registering as a delegate lets us see delivered notifications; the
        // user still controls delivery through System Settings.
        center.setNotificationCategories([])
    }

    public func stop() {
        UNUserNotificationCenter.current().delegate = nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called as a banner is about to be presented. We mirror it rather than
    /// replacing it, so the user still gets the normal notification.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        emitNotification(notification)
        completionHandler([.banner, .sound])
    }

    private func emitNotification(_ notification: UNNotification) {
        let content = notification.request.content
        let title = content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        emit(SystemEvent(source: .notification, payload: .notification(
            app: "Notification",
            title: title,
            body: content.body
        )))
    }
}
