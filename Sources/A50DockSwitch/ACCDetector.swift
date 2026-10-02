import AppKit

/// Detects a running Astro Command Center. It grabs the base station's vendor
/// HID interface exclusively, which blinds us — same conflict as Windows.
enum ACCDetector {
    /// Returns true if an Astro Command Center process is running.
    static func isRunning() -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, name.localizedCaseInsensitiveContains("astro") {
                return true
            }
            if let id = app.bundleIdentifier, id.localizedCaseInsensitiveContains("astro") {
                return true
            }
        }
        return false
    }

    /// Polled periodically; returns true only on the rising edge so we notify once.
    static func poll(previous: inout Bool) -> Bool {
        let now = isRunning()
        let rose = now && !previous
        previous = now
        return rose
    }
}
