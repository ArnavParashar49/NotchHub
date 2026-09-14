import CoreGraphics
import Foundation
import NotchHubCore

/// Observes display brightness changes.
///
/// macOS exposes no public brightness API. The reliable path on Apple Silicon
/// is the private `DisplayServices` framework, which can read the current
/// backlight level. Its *change-notification* registration API is unstable
/// (the framework's internal callback machinery can fault), so this listener
/// instead reads the level on a lightweight timer. Readings pass through
/// `BrightnessChangeFilter`, which reports only deliberate steps — never the
/// constant drift of auto-brightness, and never the level at start-up. The
/// poll is one cheap framework call every 0.5 s while the feature is enabled.
///
/// If `DisplayServices` is unavailable the listener degrades to the historical
/// distributed notifications, and failing that simply never emits: it never
/// guesses a value.
public final class BrightnessListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    /// Last level from the distributed-notification fallback (which only fires
    /// on user changes, so it needs no drift filter).
    private var lastLevel: Double?
    /// Filters the polled readings down to deliberate changes.
    private var filter = BrightnessChangeFilter()
    private var timer: Timer?
    private var distributedObserver: NSObjectProtocol?

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private var getBrightness: GetBrightnessFn?
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var displayID = CGMainDisplayID()

    /// How often to re-read the level: quick enough that a brightness key
    /// shows almost at once, and short enough that ambient drift between two
    /// readings stays far below `BrightnessChangeFilter.minimumStep`.
    private let pollInterval: TimeInterval = 0.5

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public func start() {
        guard timer == nil, distributedObserver == nil else { return }

        // Prefer DisplayServices (accurate level, works on Apple Silicon).
        if frameworkHandle == nil {
            if let handle = dlopen(Self.frameworkPath, RTLD_NOW) {
                frameworkHandle = handle
                if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                    getBrightness = unsafeBitCast(sym, to: GetBrightnessFn.self)
                }
            }
        }

        if getBrightness != nil {
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                self?.read()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            read()
            return
        }

        // Fallback: the historical distributed notification.
        installDistributedObserver()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }
        if let handle = frameworkHandle {
            dlclose(handle)
            frameworkHandle = nil
            getBrightness = nil
        }
        lastLevel = nil
        filter = BrightnessChangeFilter()
    }

    /// Reads the main display's brightness and emits a deliberate change.
    private func read() {
        guard let getBrightness else { return }
        var level: Float = 0
        guard getBrightness(displayID, &level) == 0 else { return }
        guard let reported = filter.accept(Double(level)) else { return }
        emit(SystemEvent(source: .brightness, payload: .brightness(level: reported)))
    }

    // MARK: - Fallback

    private func installDistributedObserver() {
        guard distributedObserver == nil else { return }
        let names = [
            "com.apple.BezelServices.BrightnessChangedNotification",
            "com.apple.controlcenter.brightness",
        ]
        let center = DistributedNotificationCenter.default()
        for name in names {
            distributedObserver = center.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.handleDistributed(note)
            }
            if distributedObserver != nil { break }
        }
    }

    private func handleDistributed(_ note: Notification) {
        let info = note.userInfo
        let raw = (info?["Brightness"] as? Double)
            ?? (info?["value"] as? Double)
            ?? (info?["brightness"] as? Double)
        guard let raw else { return }

        let level = raw > 1 ? raw / 100 : raw
        let clamped = max(0, min(1, level))
        guard clamped != lastLevel else { return }
        lastLevel = clamped
        emit(SystemEvent(source: .brightness, payload: .brightness(level: clamped)))
    }
}
