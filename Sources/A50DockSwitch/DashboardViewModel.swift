import Foundation
import SwiftUI
import os
import A50HID

private let log = Logger(subsystem: "com.a50.dockswitch", category: "dashboard")

/// Loads and mutates headset settings (EQ / sidetone / mic / noise gate) off
/// the main thread. Shares one AstroHID client for the dashboard's lifetime.
///
/// Writes are applied **optimistically**: the local snapshot updates the moment
/// the user commits a control, and only a *failing* write re-reads the device.
/// Re-reading on every change would cost ~9 HID round trips (≈0.5s), all
/// serialized behind AppState's poll timer on the shared client — visibly laggy
/// while dragging an EQ band.
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var settings: AstroHID.HeadsetSettings?
    @Published var loading = false
    @Published var saving = false
    @Published var lastError: String?
    @Published var notice: String?

    /// The app's shared client (seizing means one client per process).
    private let hid: AstroHID

    init(hid: AstroHID) {
        self.hid = hid
    }

    func refresh() {
        guard !loading, !saving else {
            log.debug("refresh skipped (loading=\(self.loading, privacy: .public) saving=\(self.saving, privacy: .public))")
            return
        }
        loading = true
        lastError = nil
        let t0 = Date()
        Task.detached { [hid] in
            let result: Result<AstroHID.HeadsetSettings, Error>
            do { result = .success(try hid.getHeadsetSettings()) }
            catch { result = .failure(error) }
            await MainActor.run {
                switch result {
                case .success(let s):
                    let ms = Int(Date().timeIntervalSince(t0) * 1000)
                    log.info("refresh ok in \(ms, privacy: .public)ms dirty=\(s.hasUnsavedChanges, privacy: .public) side=\(s.sidetoneActive, privacy: .public)/\(s.sidetoneSaved, privacy: .public)")
                    self.settings = s
                case .failure(let e):
                    log.error("refresh failed: \( "\(e)", privacy: .public)")
                    self.lastError = "\(e)"
                }
                self.loading = false
            }
        }
    }

    /// Applies `mutate` to the local snapshot immediately, then performs `write`
    /// on the HID client. If the device rejects it, the snapshot is restored
    /// from the device so the UI never lies about headset state.
    private func write(
        _ mutate: @escaping (inout AstroHID.HeadsetSettings) -> Void,
        _ write: @escaping (AstroHID) throws -> Void,
        message: String,
        refreshOnSuccess: Bool = false
    ) {
        guard var snapshot = settings else { return }
        mutate(&snapshot)
        settings = snapshot
        lastError = nil
        notice = nil
        Task.detached { [hid] in
            do {
                try write(hid)
                if refreshOnSuccess {
                    await MainActor.run { self.refresh() }
                }
            } catch {
                await MainActor.run {
                    self.lastError = "\(message): \(error)"
                    self.refresh()   // restore truth from the device
                }
            }
        }
    }

    // MARK: - Writes

    func setSidetone(_ value: Int) {
        write({ $0.sidetoneActive = value },
              { try $0.setSidetone(value) },
              message: "Sidetone")
    }

    func setMic(_ value: Int) {
        write({ $0.micActive = value },
              { try $0.setMicLevel(value) },
              message: "Mic level")
    }

    /// Switching preset invalidates gains, frequencies and names, so the
    /// snapshot is re-read after the write rather than patched in place.
    func setEqPreset(_ preset: Int) {
        write({ $0.eqPreset = preset },
              { try $0.setActiveEqPreset(preset) },
              message: "EQ preset",
              refreshOnSuccess: true)
    }

    func setNoiseGate(_ mode: Int) {
        write({ $0.noiseGate = mode },
              { try $0.setNoiseGate(AstroHID.NoiseGate(rawValue: mode) ?? .home) },
              message: "Noise gate")
    }

    func setEqGain(_ index: Int, _ db: Int) {
        guard var gains = settings?.eqGains, gains.indices.contains(index) else { return }
        gains[index] = db
        let preset = settings?.eqPreset ?? 1
        write({ $0.eqGains = gains },
              { try $0.setEqGains(preset: preset, gains: gains) },
              message: "EQ gain")
    }

    // MARK: - Persistence

    /// Writes the active configuration to the headset's own storage. Without
    /// this, changes are discarded when the base station powers off.
    func save() {
        guard !saving else { return }
        saving = true
        lastError = nil
        notice = nil
        Task.detached { [hid] in
            do {
                log.info("save: sending SAVE_VALUES")
                try hid.saveValues()
                log.info("save: acknowledged by base station")
            } catch {
                log.error("save failed: \( "\(error)", privacy: .public)")
                await MainActor.run {
                    self.lastError = "Save failed: \(error)"
                    self.saving = false
                }
                return
            }
            // `SAVE_VALUES` acking *is* the save, but a read started too soon
            // afterwards can answer with the pre-save `saved` values (or a junk
            // frame), which would leave the panel claiming unsaved changes.
            // Confirm against the device before declaring success.
            for attempt in 1...4 {
                usleep(700_000)
                guard let s = try? hid.getHeadsetSettings() else {
                    log.warning("save: confirm attempt \(attempt, privacy: .public) unreadable")
                    continue
                }
                if !s.hasUnsavedChanges {
                    log.info("save: confirmed clean on attempt \(attempt, privacy: .public)")
                    await MainActor.run {
                        self.settings = s
                        self.saving = false
                        self.notice = "Saved to headset"
                    }
                    return
                }
                log.info("save: attempt \(attempt, privacy: .public) still dirty side=\(s.sidetoneActive, privacy: .public)/\(s.sidetoneSaved, privacy: .public)")
            }
            log.warning("save: unconfirmed after 4 attempts, falling back to refresh")
            await MainActor.run {
                self.saving = false
                self.notice = "Saved to headset"
                self.refresh()   // last resort: let the user's Refresh decide
            }
        }
    }
}
