import Foundation
import A50HID

/// --battest: dump raw 0x7C payloads to see why the percentage flaps.
func batteryTestMain(_ n: Int) {
    let c = AstroHID()
    for i in 0..<n {
        do {
            let p = try c.rawQuery(0x7C)
            let hex = p.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[\(i)] len=\(p.count) \(hex)")
        } catch {
            print("[\(i)] FAIL \(error)")
        }
        usleep(300_000)
    }
}
