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
        static let saveValues: UInt8 = 0x61
        static let setSlider: UInt8 = 0x62
        static let setEqGain: UInt8 = 0x63
        static let setNoiseGate: UInt8 = 0x64
        static let setEqPreset: UInt8 = 0x67
        static let getSlider: UInt8 = 0x68
        static let getEqGain: UInt8 = 0x69
        static let getNoiseGate: UInt8 = 0x6A
        static let getEqPreset: UInt8 = 0x6C
        static let getEqName: UInt8 = 0x6E
        static let getEqFreqAndBW: UInt8 = 0x70
        static let getBalance: UInt8 = 0x72
        static let getDefaultBalance: UInt8 = 0x77
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

    /// Noise gate replies `[0x6A, active, saved]`.
    public func getNoiseGate() throws -> (active: Int, saved: Int) {
        let p = try rawQuery(Cmd.getNoiseGate)
        guard p.count >= 2, p[0] == Cmd.getNoiseGate else { throw HIDError.badFrame }
        return (Int(p[1]), p.count >= 3 ? Int(p[2]) : Int(p[1]))
    }

    public func getBalance() throws -> Int {
        let p = try rawQuery(Cmd.getBalance)
        guard let first = p.first else { throw HIDError.badFrame }
        return Int(first)
    }

    /// Center frequency (Hz) of each band in a preset, index 0 == band 1.
    ///
    /// Bands 1 and 5 are shelving filters and report bandwidth 0. The reply is
    /// `[0x70, preset, band, bw, savedBW, center, savedCenter]` as little-endian
    /// u16 from offset 3.
    public func getEqFreqs(preset: Int) throws -> [Int] {
        var freqs: [Int] = []
        for band in 1...5 {
            let p = try rawQuery(Cmd.getEqFreqAndBW, payload: [UInt8(preset), UInt8(band)])
            guard p.count >= 11, p[0] == Cmd.getEqFreqAndBW else { throw HIDError.badFrame }
            freqs.append(Int(p[7]) | (Int(p[8]) << 8))
        }
        return freqs
    }

    /// Default game:voice balance — 0 is 100% game, 255 is 100% chat. This is
    /// what the balance returns until the buttons on the headset override it.
    public func getDefaultBalance() throws -> (active: Int, saved: Int) {
        let active = try rawQuery(Cmd.getDefaultBalance, payload: [0])
        let saved = try rawQuery(Cmd.getDefaultBalance, payload: [1])
        guard let a = active.first, let s = saved.first else { throw HIDError.badFrame }
        return (Int(a), Int(s))
    }

    /// Persist the active configuration (EQ, sliders, noise gate) to the
    /// headset. Without this, every write is discarded when the base station
    /// powers off.
    ///
    /// The reply takes ~2s, well past the default 1s exchange timeout.
    public func saveValues() throws {
        let p = try rawQuery(Cmd.saveValues, retries: 3, timeout: 3.0)
        guard p.count >= 2, p[0] == Cmd.saveValues else { throw HIDError.badFrame }
        guard p[1] == 0 else { throw HIDError.deviceError("save rejected") }
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
        public var eqSavedGains: [Int]
        public var eqFreqs: [Int]
        public var eqNames: [String]
        public var noiseGate: Int
        public var noiseGateSaved: Int
        public var balance: Int
        public var defaultBalance: Int
        public var defaultBalanceSaved: Int

        /// True when a value we wrote differs from what is stored on the
        /// headset — i.e. `saveValues()` would actually do something.
        public var hasUnsavedChanges: Bool {
            eqGains != eqSavedGains
                || sidetoneActive != sidetoneSaved
                || micActive != micSaved
                || noiseGate != noiseGateSaved
        }

        /// GAME share of the current balance, 0...100.
        public var gamePercent: Int { Int((Double(255 - balance) / 255.0 * 100).rounded()) }

        /// GAME share of the stored default balance, 0...100.
        public var defaultGamePercent: Int { Int((Double(255 - defaultBalance) / 255.0 * 100).rounded()) }
    }

    public func getHeadsetSettings() throws -> HeadsetSettings {
        let side = try getSlider(.sidetone)
        let mic = try getSlider(.mic)
        let preset = try getActiveEqPreset()
        let p = try rawQuery(Cmd.getEqGain, payload: [UInt8(preset)])
        guard p.count >= 7 else { throw HIDError.badFrame }
        let gains = (2..<7).map { Int(p[$0]) - 12 }
        let savedGains = p.count >= 12 ? (7..<12).map { Int(p[$0]) - 12 } : gains
        var names: [String] = []
        for n in 1...3 {
            names.append((try? getEqPresetName(n)) ?? "PRESET \(n)")
        }
        let freqs = (try? getEqFreqs(preset: preset)) ?? Array(repeating: 0, count: 5)
        let gate = try getNoiseGate()
        let balance = try getBalance()
        let defBalance = (try? getDefaultBalance()) ?? (active: balance, saved: balance)
        return HeadsetSettings(
            sidetoneActive: side.active, sidetoneSaved: side.saved,
            micActive: mic.active, micSaved: mic.saved,
            eqPreset: preset, eqGains: gains, eqSavedGains: savedGains,
            eqFreqs: freqs, eqNames: names,
            noiseGate: gate.active, noiseGateSaved: gate.saved,
            balance: balance,
            defaultBalance: defBalance.active, defaultBalanceSaved: defBalance.saved
        )
    }
}
