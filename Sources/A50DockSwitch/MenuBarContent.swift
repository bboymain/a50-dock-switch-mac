import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.state.rawValue)
        Text(state.batteryText.isEmpty ? "Battery: --" : "Battery\(state.batteryText)")
        if state.accRunning {
            Text("⚠ close ASTRO Command Center")
        }

        Divider()

        Button("Headset Dashboard…") {
            // An LSUIElement (accessory) app can't become frontmost, so its
            // window never repaints reliably and never takes keyboard focus.
            // Promote to a regular app for as long as the dashboard is open.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "dashboard")
        }
        .keyboardShortcut("d")

        Button(state.config.paused ? "Resume" : "Pause") {
            state.togglePause()
        }

        Toggle("Notifications", isOn: Binding(
            get: { state.config.notifications },
            set: { _ in state.toggleNotifications() }
        ))

        Toggle("Start at login", isOn: Binding(
            get: { state.loginItemEnabled },
            set: { state.setLoginItem($0) }
        ))

        Divider()

        Menu("Default device: \(state.defaultDeviceName)") {
            ForEach(state.devices) { device in
                Button(device.name) { state.manualSwitch(uid: device.uid) }
            }
        }

        Menu("Undocked output: \(state.config.undockedName.isEmpty ? "Auto" : state.config.undockedName)") {
            ForEach(state.devices) { device in
                Button(device.name) { state.setUndockedDevice(device) }
            }
            Button("Refresh device list") { state.refreshDevices() }
        }

        Menu("Docked output: \(state.config.dockedName.isEmpty ? "Auto" : state.config.dockedName)") {
            ForEach(state.devices) { device in
                Button(device.name) { state.setDockedDevice(device) }
            }
            Button("Refresh device list") { state.refreshDevices() }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
