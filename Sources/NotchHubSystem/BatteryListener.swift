import Foundation
import IOKit.ps

/// Observes battery level and charging state via IOKit power sources.
///
/// Emits only on change, so the island is not woken by a steady battery.
public final class BatteryListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var runLoopSource: CFRunLoopSource?
    private var lastPercent: Int?
    private var lastCharging: Bool?
    private var didWarnLow = false

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public func start() {
        guard runLoopSource == nil else { return }
        read()

        // IOKit calls back on a C function pointer; the context carries us through.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let listener = Unmanaged<BatteryListener>.fromOpaque(ctx).takeUnretainedValue()
            listener.read()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        runLoopSource = nil
    }

    /// Reads the current power source snapshot and emits on change.
    private func read() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                let percent = description[kIOPSCurrentCapacityKey as String] as? Int
            else { continue }

            let charging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false

            if percent != lastPercent || charging != lastCharging {
                // The first reading and a percentage ticking down are status;
                // only plugging in or unplugging is news.
                let chargingChanged = lastCharging != nil && charging != lastCharging
                lastPercent = percent
                lastCharging = charging
                emit(SystemEvent(source: .battery, payload: .battery(
                    percent: percent,
                    charging: charging,
                    chargingChanged: chargingChanged
                )))
            }

            if percent <= 10, !charging, !didWarnLow {
                didWarnLow = true
                emit(SystemEvent(source: .battery, payload: .lowBattery(percent: percent)))
            } else if percent > 15 || charging {
                didWarnLow = false
            }
            return
        }
    }
}
