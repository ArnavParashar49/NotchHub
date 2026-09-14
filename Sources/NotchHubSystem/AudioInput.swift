import CoreAudio
import Foundation

/// Who is capturing audio input right now.
enum AudioInput {

    /// Whether any process is capturing from the default input device.
    ///
    /// CoreAudio keeps a device-wide flag for this; it is accurate and needs no
    /// permission of its own — but it cannot say WHICH process.
    static func isInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else {
            return false
        }

        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    /// Bundle identifiers of the processes currently capturing input, or `nil`
    /// on macOS versions without CoreAudio's process objects (before 14.2).
    static func capturingBundleIDs() -> Set<String>? {
        guard #available(macOS 14.2, *) else { return nil }

        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &processes) == noErr else { return nil }

        var result = Set<String>()
        for process in processes {
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { continue }

            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundle: Unmanaged<CFString>?
            let status = withUnsafeMutablePointer(to: &bundle) { pointer in
                AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, pointer)
            }
            guard status == noErr, let value = bundle?.takeRetainedValue() else { continue }
            let id = value as String
            if !id.isEmpty { result.insert(id) }
        }
        return result
    }
}
