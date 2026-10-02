import Foundation
import SwiftUI
import UserNotifications
import os
import A50HID

private let log = Logger(subsystem: "com.a50.dockswitch", category: "app")

enum DockState: String {
    case undocked = "Headphones (undocked)"
    case docked = "Docked — speakers"
    case off = "Headset off — speakers"
    case paused = "Paused"
    case error = "Base station not found"
    case accConflict = "Astro Command Center is running"
}

/// One line in the dashboard's event history, mirroring upstream's log panel.
struct HistoryEntry: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var state: DockState = .error
    @Published var batteryText: String = ""
    @Published var charge: Int?
    @Published var charging: Bool = false
    @Published var defaultDeviceName: String = ""
    @Published var devices: [AudioOutputDevice] = []
    @Published var config: AppConfig = Config.shared.data
    @Published var accRunning: Bool = false
    @Published var loginItemEnabled: Bool = false
    @Published var themeName: String = ThemeStore.current
    @Published var history: [HistoryEntry] = []

    /// Shared HID client. Seizing the interface means only one client per
    /// process can exist — the dashboard reuses this one.
    let hid = AstroHID()
    private var pollTimer: Timer?
    private var pending: DockState? = nil
    private var pendingCount = 0
    private var applied: DockState? = nil
    private var cycle = 0

    init() {
        ensureDeviceConfig()
        refreshDevices()
        defaultDeviceName = AudioDevices.shared.defaultOutputName() ?? ""
        loginItemEnabled = LoginItem.isEnabled
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        start()
    }

    func start() {
        stop()
        log.info("A50 Dock Switch starting — docked=\(Config.shared.data.dockedName, privacy: .public) undocked=\(Config.shared.data.undockedName, privacy: .public)")
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
    }

    func stop() { pollTimer?.invalidate(); pollTimer = nil }

    /// Appends to the dashboard's event history (newest first, capped).
    private func record(_ text: String) {
        history.insert(HistoryEntry(date: Date(), text: text), at: 0)
        if history.count > 60 { history.removeLast(history.count - 60) }
    }

    func refreshDevices() {
        devices = AudioDevices.shared.listOutputDevices()
    }

    // MARK: - Polling

    private func tick() async {
        let data = Config.shared.data
        let interval = max(0.5, data.interval)
        let wantBattery = (cycle % 5 == 0)
        cycle += 1

        // Throttle: only act on ~`interval` seconds, but keep 0.5s timer for smoothness.
        if cycle % max(1, Int(interval / 0.5)) != 0 { return }

        // Every ~5s, check whether Astro Command Center has (re)opened and
        // claimed the base station's HID interface.
        if cycle % 10 == 0 {
            let rose = ACCDetector.poll(previous: &accRunning)
            if rose {
                log.warning("ASTRO Command Center detected running — it will fight for the HID interface")
                record("ASTRO Command Center detected")
                notify("ASTRO Command Center is running — close it or dock switching won't work")
            }
        }

        let readTask = Task.detached { [hid] () -> (AstroHID.HeadsetStatus?, AstroHID.BatteryStatus?, Error?) in
            do {
                let headset = try hid.getHeadsetStatus()
                var battery: AstroHID.BatteryStatus? = nil
                if wantBattery { battery = try? hid.getBatteryStatus() }
                return (headset, battery, nil)
            } catch {
                return (nil, nil, error)
            }
        }
        let (headset, battery, error) = await readTask.value

        if let error {
            let newState: DockState = data.paused ? .paused : (accRunning ? .accConflict : .error)
            if newState != state { log.error("state -> \(newState.rawValue, privacy: .public): \( "\(error)", privacy: .public)") }
            state = newState
            charge = nil
            batteryText = ""
            hid.close()
            _ = error
            defaultDeviceName = AudioDevices.shared.defaultOutputName() ?? ""
            return
        }

        guard let headset else { return }
        let newState: DockState = headset.isDocked ? .docked : (headset.isOn ? .undocked : .off)

        if newState != state {
            log.info("state -> \(newState.rawValue, privacy: .public) (docked=\(headset.isDocked), on=\(headset.isOn))")
            record("State → \(newState.rawValue)")
        }

        if let battery {
            if charge != battery.chargePercent || charging != battery.isCharging {
                log.info("battery -> \(battery.chargePercent)% charging=\(battery.isCharging)")
            }
            charge = battery.chargePercent
            charging = battery.isCharging
            batteryText = "  \(battery.chargePercent)%\(battery.isCharging ? " (charging)" : "")"
        }

        if data.paused {
            state = .paused
            applied = newState
            defaultDeviceName = AudioDevices.shared.defaultOutputName() ?? ""
            return
        }

        let cmd = Config.shared
        if newState == pending {
            pendingCount += 1
        } else {
            pending = newState
            pendingCount = 1
        }

        guard pendingCount >= max(1, data.debounce) else {
            state = newState == applied ? newState : state
            return
        }

        if newState != applied {
            let (uid, name) = targetDevice(for: newState, config: cmd.data)
            if uid.isEmpty {
                applied = newState
            } else if AudioDevices.shared.setDefaultOutput(uid: uid) {
                applied = newState
                log.info("switched default output -> \(name, privacy: .public)")
                record("Switched output → \(name)")
                notify(newState == .undocked ? "Headphones active" : (newState == .off ? "Speakers active (headset off)" : "Speakers active (docked)"))
                _ = name
            } else {
                state = .error
                defaultDeviceName = AudioDevices.shared.defaultOutputName() ?? ""
                return
            }
        }

        state = newState
        defaultDeviceName = AudioDevices.shared.defaultOutputName() ?? ""
    }

    private func targetDevice(for state: DockState, config: AppConfig) -> (String, String) {
        switch state {
        case .undocked: return (config.undockedUID, config.undockedName)
        default: return (config.dockedUID, config.dockedName)
        }
    }

    // MARK: - Commands

    func togglePause() {
        Config.shared.update { $0.paused.toggle() }
        config = Config.shared.data
        if Config.shared.data.paused {
            state = .paused
            record("Automation paused")
        } else {
            record("Automation resumed")
        }
    }

    func manualSwitch(uid: String) {
        guard AudioDevices.shared.setDefaultOutput(uid: uid) else { return }
        applied = pending
        defaultDeviceName = AudioDevices.shared.defaultOutputName() ?? ""
        if let name = devices.first(where: { $0.uid == uid })?.name {
            record("Manual switch → \(name)")
            notify("Manual: " + name)
        }
    }

    func setDockedDevice(_ device: AudioOutputDevice) {
        Config.shared.update {
            $0.dockedUID = device.uid
            $0.dockedName = device.name
        }
        config = Config.shared.data
    }

    func setUndockedDevice(_ device: AudioOutputDevice) {
        Config.shared.update {
            $0.undockedUID = device.uid
            $0.undockedName = device.name
        }
        config = Config.shared.data
    }

    func toggleNotifications() {
        Config.shared.update { $0.notifications.toggle() }
        config = Config.shared.data
    }

    func setLoginItem(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        loginItemEnabled = LoginItem.isEnabled
    }

    func setTheme(_ id: String) {
        guard id != themeName else { return }
        ThemeStore.current = id
        themeName = id
    }

    func setPollInterval(_ seconds: Double) {
        let clamped = max(0, min(30, seconds))
        guard clamped != config.interval else { return }
        Config.shared.update { $0.interval = clamped }
        config = Config.shared.data
    }

    func setDebounce(_ reads: Int) {
        let clamped = max(1, min(10, reads))
        guard clamped != config.debounce else { return }
        Config.shared.update { $0.debounce = clamped }
        config = Config.shared.data
    }

    // MARK: - Helpers

    private func ensureDeviceConfig() {
        let data = Config.shared.data
        guard data.dockedUID.isEmpty || data.undockedUID.isEmpty else { return }
        // Skip virtual/helper devices (e.g. "Background Music" from the BGM app)
        // and the A50's own Voice interface.
        let devices = AudioDevices.shared.listOutputDevices().filter { d in
            let n = d.name.lowercased()
            return !n.contains("background music") && !n.contains("(ui sounds)")
                && !n.contains("a50 voice")
        }
        var undocked: AudioOutputDevice?
        var docked: AudioOutputDevice?
        for d in devices {
            let n = d.name.lowercased()
            if n.contains("a50") && n.contains("game") && undocked == nil { undocked = d }
            if n.contains("a50") { continue }
            if docked == nil { docked = d }
        }
        if undocked == nil { undocked = devices.first(where: { $0.name.lowercased().contains("a50") }) }
        if undocked == nil || docked == nil { return }
        Config.shared.update {
            $0.undockedUID = undocked!.uid
            $0.undockedName = undocked!.name
            $0.dockedUID = docked!.uid
            $0.dockedName = docked!.name
        }
    }

    private func notify(_ message: String) {
        guard Config.shared.data.notifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "A50 Dock Switch"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
