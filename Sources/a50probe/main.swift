import Foundation
import A50HID

/// Protocol diagnostic tool, like probe.py from the Windows repo.
/// Usage:
///   a50probe              list interfaces + read 5 snapshots (2s apart)
///   a50probe --list       list HID interfaces only
///   a50probe --cmd 0x54   raw dump of a single command payload
func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")
}

func listInterfaces() {
    let devices = AstroHID.listMatchedDevices()
    if devices.isEmpty {
        print("No A50 HID interfaces found (VID 0x9886 / PID 0x002C).")
        print("Plug in the base station over USB and re-run.")
        return
    }
    print("Found \(devices.count) HID interface(s):")
    for (i, d) in devices.enumerated() {
        print("""
          [\(i)] product: \(d.product)
              transport: \(d.transport)  VID 0x\(String(d.vendorID, radix: 16)) PID 0x\(String(d.productID, radix: 16))
              usage page 0x\(String(d.usagePage, radix: 16)) / usage 0x\(String(d.usage, radix: 16))
              openable: \(d.openable ? "yes" : "no")
        """)
    }
}

let args = CommandLine.arguments

if args.contains("--watch") {
    // Live state with change detection — for debugging dock/undock transitions.
    setvbuf(stdout, nil, _IONBF, 0)  // flush every line so `timeout`/pipes keep it
    let client = AstroHID()
    var last = ""
    print("watching dock/on/battery (ctrl-c to stop)...\n")
    while true {
        var line: String
        do {
            let h = try client.getHeadsetStatus()
            let b = try? client.getBatteryStatus()
            line = "docked=\(h.isDocked) on=\(h.isOn)"
            if let b { line += " battery=\(b.chargePercent)%\(b.isCharging ? " (charging)" : "")" }
        } catch {
            line = "ERROR: \(error)"
        }
        if line != last {
            let ts = ISO8601DateFormatter().string(from: Date())
            print("[\(ts)] \(line)")
            last = line
        }
        usleep(500_000)
    }
}

if let wIndex = args.firstIndex(of: "--wtest"), args.index(after: wIndex) < args.endIndex {
    let v = Int(args[args.index(after: wIndex)]) ?? 50
    writeTestMain(v)
    exit(0)
}

if args.contains("--idle") {
    let idx = args.firstIndex(of: "--idle")!
    var secs = 5.0
    if let v = args.index(after: idx) < args.endIndex ? args[args.index(after: idx)] : nil {
        secs = Double(v) ?? 5.0
    }
    idleTestMain(seconds: secs)
    exit(0)
}

if let bIndex = args.firstIndex(of: "--battest"), args.index(after: bIndex) < args.endIndex {
    setvbuf(stdout, nil, _IONBF, 0)
    let n = Int(args[args.index(after: bIndex)]) ?? 8
    batteryTestMain(n)
    exit(0)
}

if args.contains("--settings") {
    let client = AstroHID()
    print("Reading headset settings...\n")
    do {
        let s = try client.getHeadsetSettings()
        print("sidetone      : \(s.sidetoneActive) (saved \(s.sidetoneSaved))")
        print("mic level     : \(s.micActive) (saved \(s.micSaved))")
        print("eq preset     : \(s.eqPreset) — \(s.eqNames[min(s.eqPreset - 1, s.eqNames.count - 1)])")
        print("eq gains      : \(s.eqGains)")
        print("noise gate    : \(s.noiseGate) (0=Streaming 1=Night 2=Home 3=Tournament)")
        print("game:voice    : \(s.balance)")
    } catch {
        print("FAILED: \(error)")
        exit(1)
    }
    exit(0)
}

if args.contains("--devices") {
    devicesMain()
    exit(0)
}

if args.contains("--qtest") {
    FileHandle.standardError.write(Data("creating client\n".utf8))
    let c = AstroHID()
    FileHandle.standardError.write(Data("query 0x03\n".utf8))
    do {
        let p = try c.rawQuery(0x03)
        FileHandle.standardError.write(Data("devinfo ok: \(p.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("devinfo fail: \(error)\n".utf8))
    }
    FileHandle.standardError.write(Data("query 0x54\n".utf8))
    do {
        let s = try c.getHeadsetStatus()
        FileHandle.standardError.write(Data("hdstatus docked=\(s.isDocked) on=\(s.isOn)\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("hdstatus fail: \(error)\n".utf8))
    }
    FileHandle.standardError.write(Data("DONE\n".utf8))
    exit(0)
}


if args.contains("--enum-test") {
    enumTestMain()
    exit(0)
}

if args.contains("--raw-test") {
    rawTestMain()
    exit(0)
}

if args.contains("--list") {
    listInterfaces()
    exit(0)
}

if let cmdIndex = args.firstIndex(of: "--cmd"), args.index(after: cmdIndex) < args.endIndex {
    let cmdString = args[args.index(after: cmdIndex)]
    let value = UInt8(cmdString.hasPrefix("0x") ? strtoul(cmdString, nil, 16) : strtoul(cmdString, nil, 10))
    let client = AstroHID()
    print("Raw query 0x\(String(value, radix: 16, uppercase: true)) ...")
    do {
        let payload = try client.rawQuery(value)
        print("payload (\(payload.count) bytes): \(hex(payload))")
    } catch {
        print("FAILED: \(error)")
        exit(1)
    }
    exit(0)
}

listInterfaces()
if AstroHID.listMatchedDevices().isEmpty {
    print("\nNo device to probe.")
    exit(0)
}
print("\nReading 5 snapshots (2s apart). Dock/undock the headset to see changes.\n")

let client = AstroHID()
for i in 0..<5 {
    do {
        let headset = try client.getHeadsetStatus()
        let battery = try? client.getBatteryStatus()
        var line = "[\(i)] docked=\(headset.isDocked) on=\(headset.isOn)"
        if let battery {
            line += " battery=\(battery.chargePercent)% charging=\(battery.isCharging)"
        }
        if let info = client.currentInterfaceInfo() {
            line += "  (\(info))"
        }
        print(line)
    } catch {
        print("[\(i)] READ FAIL: \(error)")
        exit(2)
    }
    if i < 4 { sleep(2) }
}
print("\nDONE")
