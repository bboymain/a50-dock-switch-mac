import Foundation
import CoreAudio

struct AudioOutputDevice: Identifiable, Hashable {
    var id: AudioDeviceID
    var name: String
    var uid: String
}

final class AudioDevices {
    static let shared = AudioDevices()

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func listOutputDevices() -> [AudioOutputDevice] {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }

        var result: [AudioOutputDevice] = []
        for device in devices {
            guard hasOutput(device), let name = stringProp(device, kAudioObjectPropertyName), let uid = stringProp(device, kAudioDevicePropertyDeviceUID) else { continue }
            result.append(AudioOutputDevice(id: device, name: name, uid: uid))
        }
        return result
    }

    private func hasOutput(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        return buffer.withUnsafeMutableBytes { ptr -> Bool in
            guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, ptr.baseAddress!) == noErr else { return false }
            let list = ptr.baseAddress!.assumingMemoryBound(to: AudioBufferList.self)
            return list.pointee.mNumberBuffers > 0
        }
    }

    private func stringProp(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cfString: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let result = withUnsafeMutablePointer(to: &cfString) { ptr in
            AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
        }
        guard result == noErr, let value = cfString?.takeRetainedValue() else { return nil }
        return value as String
    }

    func defaultOutputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr else { return nil }
        return device
    }

    func defaultOutputName() -> String? {
        guard let id = defaultOutputDeviceID() else { return nil }
        return stringProp(id, kAudioObjectPropertyName)
    }

    @discardableResult
    func setDefaultOutput(uid: String) -> Bool {
        guard let device = listOutputDevices().first(where: { $0.uid == uid }) else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = device.id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr
    }
}
