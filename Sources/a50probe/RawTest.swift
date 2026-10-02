import Foundation
import IOKit
import IOKit.hid

func hexs(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

func decodeResponse(_ raw: [UInt8]) -> String {
    guard raw.count >= 3, raw[0] == 0x02 else { return "bad frame: " + hexs(raw) }
    let status = raw[1]
    let len = min(Int(raw[2]), raw.count - 3)
    let data = Array(raw[3..<(3 + len)])
    switch status {
    case 2:
        return "OK payload=\(hexs(data))"
    case 1:
        let msgData = data.count > 4 ? Array(data[4...]) : data
        let msg = msgData.prefix { $0 != 0 }.reduce("") { $0 + String(UnicodeScalar($1)) }
        return "ERR \(msg)"
    case 0:
        return "NO_RESP payload=\(hexs(data))"
    default:
        return "status=\(status) \(hexs(raw))"
    }
}

func rawTestMain() {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey as String: 0x9886] as CFDictionary)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = set.first else {
        print("no device"); return
    }
    print("open: 0x\(String(UInt32(bitPattern: IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))), radix: 16))")

    // Keep ONE callback registered for the whole test; respond via a queue.
    final class Sink {
        let lock = NSLock()
        var latest: [UInt8] = []
        var seq = 0
        func push(_ b: [UInt8]) { lock.lock(); latest = b; seq += 1; lock.unlock() }
        func snapshot() -> ([UInt8], Int) { lock.lock(); defer { lock.unlock() }; return (latest, seq) }
    }
    let sink = Sink()
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65)
    buf.initialize(repeating: 0, count: 65)
    IOHIDDeviceRegisterInputReportCallback(dev, buf, 65, {
        (context: UnsafeMutableRawPointer?, _ r: IOReturn, _ s: UnsafeMutableRawPointer?,
         _ t: IOHIDReportType, _ id: UInt32, _ report: UnsafeMutablePointer<UInt8>, _ len: CFIndex) in
        guard let context else { return }
        let sk = Unmanaged<Sink>.fromOpaque(context).takeUnretainedValue()
        sk.push([UInt8](UnsafeBufferPointer(start: report, count: Int(len))))
    }, Unmanaged.passUnretained(sink).toOpaque())
    IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

    func exchange(label: String, reportID: CFIndex, request: [UInt8]) {
        let (_, before) = sink.snapshot()
        var req = request
        let count = req.count
        let r = req.withUnsafeMutableBytes { p -> IOReturn in
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, reportID, p.baseAddress!.assumingMemoryBound(to: UInt8.self), count)
        }
        guard r == kIOReturnSuccess else {
            print("\(label): setOutput=0x\(String(UInt32(bitPattern: r), radix: 16))")
            return
        }
        let deadline = Date().addingTimeInterval(1.0)
        var seq = before
        var bytes: [UInt8] = []
        while Date() < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, 0.05, true)
            let (b, s) = sink.snapshot()
            if s > before { bytes = b; seq = s; break }
        }
        _ = seq
        print("\(label) → \(bytes.isEmpty ? "timeout" : decodeResponse(bytes))")
    }

    // Sweep: commands x framing variants
    let commands: [(UInt8, String)] = [
        (0x03, "devinfo"), (0x54, "hdstatus"), (0x7C, "battery"),
        (0x55, "basefw"), (0x6C, "eqpreset"), (0x72, "balance"),
        (0x6A, "noisegate"), (0x68, "slider05"),
    ]
    for (cmd, name) in commands {
        exchange(label: "rid=02 [02 \(name)]", reportID: 0x02, request: [0x02, cmd])
    }
    print("--- hidapi style: reportID passed separately, buffer WITHOUT report id ---")
    for (cmd, name) in commands {
        exchange(label: "rid=02 [\(name)]      ", reportID: 0x02, request: [cmd])
    }
    print("--- with explicit zero payload length ---")
    for (cmd, name) in commands {
        exchange(label: "rid=02 [02 \(name) 00] ", reportID: 0x02, request: [0x02, cmd, 0x00])
    }
    print("--- slider 0x68 with payload 0x05 (sidetone) ---")
    exchange(label: "rid=02 [02 68 01 05]", reportID: 0x02, request: [0x02, 0x68, 0x01, 0x05])
    exchange(label: "rid=02 [68 01 05]    ", reportID: 0x02, request: [0x68, 0x01, 0x05])
}
