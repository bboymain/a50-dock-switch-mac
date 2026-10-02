import Foundation
import CoreAudio

/// Lists output devices with their UIDs (for config.json).
func devicesMain() {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 4096
    var scratch = [UInt8](repeating: 0, count: 4096)
    let ok = scratch.withUnsafeMutableBytes { p -> Bool in
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, p.baseAddress!) == noErr
    }
    guard ok else {
        print("cannot read device list"); return
    }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
        print("cannot read device list"); return
    }

    func stringProp(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var unmanaged: Unmanaged<CFString>?
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let r = withUnsafeMutablePointer(to: &unmanaged) { AudioObjectGetPropertyData(id, &a, 0, nil, &s, $0) }
        guard r == noErr, let v = unmanaged?.takeRetainedValue() else { return nil }
        return v as String
    }

    func hasOutput(_ id: AudioDeviceID) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        var s: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &s) == noErr, s > 0 else { return false }
        var buf = [UInt8](repeating: 0, count: Int(s))
        return buf.withUnsafeMutableBytes { p -> Bool in
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, p.baseAddress!) == noErr else { return false }
            return p.baseAddress!.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers > 0
        }
    }

    // current default
    var defAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var current = AudioDeviceID(0)
    var cs = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defAddr, 0, nil, &cs, &current)

    print("Output devices:\n")
    for id in ids where hasOutput(id) {
        let name = stringProp(id, kAudioObjectPropertyName) ?? "?"
        let uid = stringProp(id, kAudioDevicePropertyDeviceUID) ?? "?"
        let marker = id == current ? "  ← current default" : ""
        print("  \(name)\(marker)")
        print("      uid: \(uid)\n")
    }
}
