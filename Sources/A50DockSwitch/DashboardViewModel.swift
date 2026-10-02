import Foundation
import SwiftUI
import A50HID

/// Loads and mutates headset settings (EQ / sidetone / mic / noise gate) off
/// the main thread. Shares one AstroHID client for the dashboard's lifetime.
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var settings: AstroHID.HeadsetSettings?
    @Published var loading = false
    @Published var lastError: String?

    /// The app's shared client (seizing means one client per process).
    private let hid: AstroHID

    init(hid: AstroHID) {
        self.hid = hid
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        lastError = nil
        Task.detached { [hid] in
            do {
                let s = try hid.getHeadsetSettings()
                await MainActor.run {
                    self.settings = s
                    self.loading = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = "\(error)"
                    self.loading = false
                }
            }
        }
    }

    private func write(_ body: @escaping (AstroHID) throws -> Void, message: String) {
        lastError = nil
        Task.detached { [hid] in
            do {
                try body(hid)
                let s = try hid.getHeadsetSettings()
                await MainActor.run {
                    self.settings = s
                }
            } catch {
                await MainActor.run {
                    self.lastError = message + ": \(error)"
                }
            }
        }
    }

    // MARK: - Writes

    func setSidetone(_ value: Int) {
        write({ try $0.setSidetone(value) }, message: "Sidetone")
    }

    func setMic(_ value: Int) {
        write({ try $0.setMicLevel(value) }, message: "Mic level")
    }

    func setEqPreset(_ preset: Int) {
        write({ try $0.setActiveEqPreset(preset) }, message: "EQ preset")
    }

    func setNoiseGate(_ mode: Int) {
        write({ try $0.setNoiseGate(AstroHID.NoiseGate(rawValue: mode) ?? .home) }, message: "Noise gate")
    }

    func setEqGain(_ index: Int, _ db: Int) {
        guard var gains = settings?.eqGains, gains.indices.contains(index) else { return }
        gains[index] = db
        let preset = settings?.eqPreset ?? 1
        write({ try $0.setEqGains(preset: preset, gains: gains) }, message: "EQ gain")
    }
}
