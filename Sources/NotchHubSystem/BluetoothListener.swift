import CoreAudio
import Foundation

/// Detects Bluetooth audio devices (AirPods, Beats, speakers) connecting and
/// disconnecting.
///
/// Uses CoreAudio rather than CoreBluetooth on purpose: CoreBluetooth needs the
/// app to hold Bluetooth permission and can only enumerate peripherals whose
/// services it already knows about, while CoreAudio answers the question the
/// island actually asks — "is a Bluetooth audio device live right now?" — with
/// no permission prompt at all. A device appearing or disappearing is exactly
/// the connection event the user cares about.
public final class BluetoothListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var listener: AudioObjectPropertyListenerBlock?
    /// Every Bluetooth audio output connected right now, by device id — so a
    /// second device leaving or arriving is reported as exactly that.
    private var connectedDevices: [AudioDeviceID: String] = [:]
    private var isRunning = false

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public var name: String { "Bluetooth" }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // The device list changes whenever anything connects or disconnects.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let onDevicesChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.poll() }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            onDevicesChanged
        ) == noErr {
            listener = onDevicesChanged
        }

        // Seed with the current state so we only emit on a real transition.
        connectedDevices = Self.bluetoothAudioDevices()
        poll()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if let listener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
            )
        }
        listener = nil
    }

    private func poll() {
        let current = Self.bluetoothAudioDevices()
        guard current != connectedDevices else { return }
        let previous = connectedDevices
        connectedDevices = current

        // Name the devices that left (e.g. "Arnav's AirPods Pro") and the ones
        // that arrived, so the island and the pet know WHAT changed — even while
        // another Bluetooth device stays connected.
        for (id, name) in previous.sorted(by: { $0.key < $1.key }) where current[id] == nil {
            emit(SystemEvent(source: .bluetooth, payload: .bluetoothDevice(connected: false, name: name)))
        }
        for (id, name) in current.sorted(by: { $0.key < $1.key }) where previous[id] == nil {
            emit(SystemEvent(source: .bluetooth, payload: .bluetoothDevice(connected: true, name: name)))
        }
    }

    // MARK: - CoreAudio enumeration

    struct AudioDevice {
        let name: String
        let isAirPods: Bool
    }

    /// Every connected Bluetooth audio device that can actually play sound.
    static func bluetoothAudioDevices() -> [AudioDeviceID: String] {
        var devices: [AudioDeviceID: String] = [:]
        for id in allDeviceIDs() where hasOutputStreams(id) && isBluetooth(id) {
            devices[id] = deviceName(id) ?? "Bluetooth device"
        }
        return devices
    }

    /// The first connected Bluetooth audio device that can actually play sound.
    static func firstBluetoothAudioDevice() -> AudioDevice? {
        guard let (_, name) = bluetoothAudioDevices().min(by: { $0.key < $1.key }) else { return nil }
        return AudioDevice(name: name, isAirPods: name.localizedCaseInsensitiveContains("airpods"))
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// True when the device has at least one output stream — i.e. it can play
    /// audio. Filters out input-only devices like a Bluetooth microphone.
    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer -> OSStatus in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        let value = name as String
        return value.isEmpty ? nil : value
    }
}
