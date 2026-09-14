import CoreAudio
import Foundation

/// Observes the default output device's volume via CoreAudio.
public final class VolumeListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var deviceID = AudioDeviceID(0)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var lastLevel: Double?
    private var isRunning = false

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // Watch for the default output device changing (headphones, AirPods…).
        var systemAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let onDeviceChange: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.attachToDefaultDevice() }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &systemAddress,
            DispatchQueue.main,
            onDeviceChange
        ) == noErr {
            systemListener = onDeviceChange
        }

        attachToDefaultDevice()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let deviceListener, deviceID != 0 {
            var address = volumeAddress()
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, deviceListener)
        }
        if let systemListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, systemListener
            )
        }
        deviceListener = nil
        systemListener = nil
        deviceID = 0
    }

    private func attachToDefaultDevice() {
        if let deviceListener, deviceID != 0 {
            var old = volumeAddress()
            AudioObjectRemovePropertyListenerBlock(deviceID, &old, DispatchQueue.main, deviceListener)
            self.deviceListener = nil
        }

        deviceID = defaultOutputDevice()
        guard deviceID != 0 else { return }

        var address = volumeAddress()
        guard AudioObjectHasProperty(deviceID, &address) else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.read(announce: true)
        }
        if AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, listener) == noErr {
            deviceListener = listener
        }
        read(announce: false)
    }

    /// Reads the level. Attaching to a device (launch, a settings change,
    /// switching outputs) only records it — the island hears about changes the
    /// user makes, not the level that happened to be set.
    private func read(announce: Bool) {
        guard deviceID != 0 else { return }
        var address = volumeAddress()
        var level = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &level)
        guard status == noErr else { return }

        let value = Double(max(0, min(1, level)))
        guard value != lastLevel else { return }
        lastLevel = value
        guard announce else { return }
        emit(SystemEvent(source: .volume, payload: .volume(level: value)))
    }

    private func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func defaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr ? device : 0
    }
}
