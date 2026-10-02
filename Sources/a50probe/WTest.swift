import Foundation
import A50HID

/// --wtest: write sidetone to a value, read it back, restore.
func writeTestMain(_ value: Int) {
    let c = AstroHID()
    do {
        let before = try c.getSlider(.sidetone)
        print("before: active=\(before.active) saved=\(before.saved)")
        try c.setSidetone(value)
        print("wrote sidetone=\(value)")
        let after = try c.getSlider(.sidetone)
        print("after : active=\(after.active) saved=\(after.saved)")
        try c.setSidetone(before.active)
        let restored = try c.getSlider(.sidetone)
        print("restored: active=\(restored.active)")
        print(after.active == value ? "WRITE OK" : "WRITE MISMATCH")
    } catch {
        print("FAILED: \(error)")
        exit(1)
    }
}
