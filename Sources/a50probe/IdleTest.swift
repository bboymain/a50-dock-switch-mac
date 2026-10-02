import Foundation
import A50HID

/// --idletest: open the device, send nothing, and report any unsolicited input
/// reports. If these exist, our response matcher can pick up the wrong one.
func idleTestMain(seconds: Double) {
    setvbuf(stdout, nil, _IONBF, 0)
    let c = AstroHID()
    print("opening + probing identity once to attach the callback...")
    _ = try? c.rawQuery(0x03)
    print("now idle for \(seconds)s, watching for unsolicited reports...")
    let start = Date()
    while Date().timeIntervalSince(start) < seconds {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        usleep(50_000)
    }
    print("(no unsolicited reports are observable through the callback API)")
}
