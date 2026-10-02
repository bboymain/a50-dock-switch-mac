import Foundation

/// Headset control + telemetry, mirroring the Windows app's `execute_hset`
/// and `telemetry_loop`. All commands run through `rawQuery` (worker thread).
extension AstroHID {
    public enum Slider: UInt8 {
        case mic = 0x04
        case sidetone = 0x05
    }

    public enum NoiseGate: Int, CaseIterable {
        case streaming = 0
        case night = 1
        case home = 2
        case tournament = 3

        public var label: String {
            switch self {
            case .streaming: return "Streaming"
            case .night: return "Night"
            case .home: return "Home"
            case .tournament: return "Tournament"
            }
        }
    }

    // Command IDs (shared by set + get).
    private enum Cmd {
        static let setSlider: UInt8 = 0x62
        static let setEqGain: UInt8 = 0x63
        static let setNoiseGate: UInt8 = 0x64
        static let setEqPreset: UInt8 = 0x67
        static let getSlider: UInt8 = 0x68
        static let getEqGain: UInt8 = 0x69
        static let getNoiseGate: UInt8 = 0x6A
        static let getEqPreset: UInt8 = 0x6C
        static let getEqName: UInt8 = 0x6E
        static let getBalance: UInt8 = 0x72
    }

    // MARK: - Setters

    public func setSlider(_ slider: Slider, value: Int) throws {
        let v = UInt8(max(0, min(100, value)))
        _ = try rawQuery(Cmd.setSlider, payload: [slider.rawValue, v])
    }

    public func setSidetone(_ value: Int) throws { try setSlider(.sidetone, value: value) }
    public func setMicLevel(_ value: Int) throws { try setSlider(.mic, value: value) }

    /// `preset` is 1...3 (matches Astro Command Center slots).
    public func setActiveEqPreset(_ preset: Int) throws {
        guard (1...3).contains(preset) else { throw HIDError.badFrame }
        _ = try rawQuery(Cmd.setEqPreset, payload: [UInt8(preset)])
    }

    /// 5 gains in dB, range -7...+7.
    public func setEqGains(preset: Int, gains: [Int]) throws {
        guard (1...3).contains(preset), gains.count == 5 else { throw HIDError.badFrame }
        let payload = [UInt8(preset)] + gains.map { UInt8(max(-7, min(7, $0)) + 12) }
        _ = try rawQuery(Cmd.setEqGain, payload: payload)
    }

    public func setNoiseGate(_ mode: NoiseGate) throws {
        _ = try rawQuery(Cmd.setNoiseGate, payload: [UInt8(mode.rawValue)])
    }

    // MARK: - Getters

    /// Slider replies are `[0x68, sliderId, activeValue, savedValue]`.
    public func getSlider(_ slider: Slider) throws -> (active: Int, saved: Int) {
        let p = try rawQuery(Cmd.getSlider, payload: [slider.rawValue])
        guard p.count >= 4, p[0] == Cmd.getSlider, p[1] == slider.rawValue else { throw HIDError.badFrame }
        return (Int(p[2]), Int(p[3]))
    }

    public func getActiveEqPreset() throws -> Int {
        let p = try rawQuery(Cmd.getEqPreset)
        guard let first = p.first else { throw HIDError.badFrame }
        return Int(first)
    }

    /// 5 gains in dB for a preset (1...3).
    public func getEqGains(preset: Int) throws -> [Int] {
        let p = try rawQuery(Cmd.getEqGain, payload: [UInt8(preset)])
        guard p.count >= 7 else { throw HIDError.badFrame }
        return (2..<7).map { Int(p[$0]) - 12 }
    }

    public func getNoiseGateMode() throws -> Int {
        let p = try rawQuery(Cmd.getNoiseGate)
        guard p.count >= 2, p[0] == Cmd.getNoiseGate else { throw HIDError.badFrame }
        return Int(p[1])
    }

    public func getBalance() throws -> Int {
        let p = try rawQuery(Cmd.getBalance)
        guard let first = p.first else { throw HIDError.badFrame }
        return Int(first)
    }

    /// Preset names reply as `[0x6E, ..., NUL-terminated UTF-8]` starting at index 2.
    public func getEqPresetName(_ preset: Int) throws -> String {
        let p = try rawQuery(Cmd.getEqName, payload: [UInt8(preset), 0])
        guard p.count > 2 else { throw HIDError.badFrame }
        let raw = p[2...].prefix { $0 != 0 }
        let name = String(decoding: raw, as: UTF8.self)
        return name.isEmpty ? "PRESET \(preset)" : name
    }

    // MARK: - Snapshot

    /// Everything the dashboard needs, in one struct.
    public struct HeadsetSettings: Sendable {
        public var sidetoneActive: Int
        public var sidetoneSaved: Int
        public var micActive: Int
        public var micSaved: Int
        public var eqPreset: Int
        public var eqGains: [Int]
        public var eqNames: [String]
        public var noiseGate: Int
        public var balance: Int
    }

    public func getHeadsetSettings() throws -> HeadsetSettings {
        let side = try getSlider(.sidetone)
        let mic = try getSlider(.mic)
        let preset = try getActiveEqPreset()
        let gains = try getEqGains(preset: preset)
        var names: [String] = []
        for p in 1...3 {
            names.append((try? getEqPresetName(p)) ?? "PRESET \(p)")
        }
        let gate = try getNoiseGateMode()
        let balance = try getBalance()
        return HeadsetSettings(
            sidetoneActive: side.active, sidetoneSaved: side.saved,
            micActive: mic.active, micSaved: mic.saved,
            eqPreset: preset, eqGains: gains, eqNames: names,
            noiseGate: gate, balance: balance
        )
    }
}
