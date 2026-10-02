import SwiftUI
import os
import A50HID

private let log = Logger(subsystem: "com.a50.dockswitch", category: "dashboard")

/// Headset control dashboard: EQ preset + per-band gains, sidetone, mic level,
/// noise gate, game/voice balance. Mirrors the controls in the Windows app.
struct DashboardView: View {
    @ObservedObject var state: AppState
    @StateObject private var vm: DashboardViewModel

    init(state: AppState) {
        log.debug("DashboardView recreated (new StateObject wrapper)")
        self.state = state
        _vm = StateObject(wrappedValue: DashboardViewModel(hid: state.hid))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusRow

                if let s = vm.settings {
                    persistenceBar(s)
                    sidetoneAndMic(s)
                    eqSection(s)
                    noiseGateSection(s)
                    balanceSection(s)
                } else if vm.loading {
                    ProgressView("Reading headset settings…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 30)
                }

                if let err = vm.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .padding(18)
        }
        .frame(width: 440, height: 660)
        .task { vm.refresh() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Label("A50 Headset Settings", systemImage: "slider.horizontal.3")
                .font(.headline)
            Spacer()
            if vm.loading { ProgressView().controlSize(.small) }
            Button("Refresh") { vm.refresh() }
                .keyboardShortcut("r")
                .disabled(vm.loading || vm.saving)
        }
    }

    /// Dock state and battery, so the dashboard doubles as a status panel —
    /// the original shows these in its title bar.
    private var statusRow: some View {
        HStack(spacing: 12) {
            Label(state.state.rawValue, systemImage: stateIcon)
                .font(.callout)
                .foregroundStyle(state.state == .error || state.state == .accConflict ? .red : .secondary)
            Spacer()
            Label(batteryLabel, systemImage: state.charging ? "battery.100.bolt" : "battery.100")
                .font(.callout.monospacedDigit())
                .foregroundStyle(state.charging ? .orange : .secondary)
        }
    }

    private var stateIcon: String {
        switch state.state {
        case .undocked: return "headphones"
        case .docked, .off: return "speaker.wave.2"
        case .paused: return "pause.circle"
        case .error, .accConflict: return "exclamationmark.triangle"
        }
    }

    private var batteryLabel: String {
        guard let charge = state.charge else { return "--%" }
        return "\(charge)%\(state.charging ? " charging" : "")"
    }

    /// Changes are written to the base station's working config only — they are
    /// gone on power-off unless `SAVE_VALUES` is sent.
    private func persistenceBar(_ s: AstroHID.HeadsetSettings) -> some View {
        HStack(spacing: 8) {
            if s.hasUnsavedChanges {
                Label("Not stored on the headset yet", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button(vm.saving ? "Saving…" : "Save to headset") { vm.save() }
                    .disabled(vm.saving)
                    .keyboardShortcut("s")
            } else if let notice = vm.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
            } else {
                Label("Stored on the headset", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.callout)
        .animation(.default, value: s.hasUnsavedChanges)
    }

    // MARK: - Sections

    private func sidetoneAndMic(_ s: AstroHID.HeadsetSettings) -> some View {
        GroupBox("Sidetone & Mic") {
            VStack(spacing: 8) {
                SliderRow(label: "Sidetone", initial: s.sidetoneActive, commit: vm.setSidetone)
                SliderRow(label: "Mic level", initial: s.micActive, commit: vm.setMic)
            }
            .padding(4)
        }
    }

    private func eqSection(_ s: AstroHID.HeadsetSettings) -> some View {
        GroupBox("Equalizer") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Preset", selection: Binding(
                    get: { s.eqPreset },
                    set: { vm.setEqPreset($0) }
                )) {
                    ForEach(1...3, id: \.self) { p in
                        Text(presetName(s, p)).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ForEach(0..<5, id: \.self) { i in
                    EqBandSlider(
                        band: bandLabel(s, i),
                        initial: s.eqGains.indices.contains(i) ? s.eqGains[i] : 0,
                        commit: { vm.setEqGain(i, $0) }
                    )
                }
                Text("dB — each band writes when you release the slider.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private func noiseGateSection(_ s: AstroHID.HeadsetSettings) -> some View {
        GroupBox("Noise Gate") {
            Picker("Mode", selection: Binding(
                get: { s.noiseGate },
                set: { vm.setNoiseGate($0) }
            )) {
                ForEach(AstroHID.NoiseGate.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(4)
        }
    }

    private func balanceSection(_ s: AstroHID.HeadsetSettings) -> some View {
        GroupBox("Game / Voice Mix") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("GAME \(s.gamePercent)% : VOICE \(100 - s.gamePercent)%")
                        .font(.callout.monospacedDigit())
                    Spacer()
                    Text("default \(s.defaultGamePercent)% game")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(s.gamePercent) / 100)
                    }
                }
                .frame(height: 6)
                Text("Changed with the buttons on the headset — the base station only reports it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Helpers

    private func presetName(_ s: AstroHID.HeadsetSettings, _ preset: Int) -> String {
        s.eqNames.indices.contains(preset - 1) ? s.eqNames[preset - 1] : "PRESET \(preset)"
    }

    /// Band center frequency from the device (`0x70`). These are *not* evenly
    /// spaced — preset 1 is 36 / 170 / 2753 / 6691 / 11002 Hz — so a hardcoded
    /// label list would misname every band.
    private func bandLabel(_ s: AstroHID.HeadsetSettings, _ index: Int) -> String {
        guard s.eqFreqs.indices.contains(index), s.eqFreqs[index] > 0 else {
            return "BAND \(index + 1)"
        }
        let freq = s.eqFreqs[index]
        return freq >= 1000
            ? String(format: "%.1f kHz", Double(freq) / 1000)
            : "\(freq) Hz"
    }
}

/// A gain slider that tracks locally while dragged and writes only on release.
private struct EqBandSlider: View {
    let band: String
    let commit: (Int) -> Void
    @State private var value: Double
    @State private var initial: Int

    init(band: String, initial: Int, commit: @escaping (Int) -> Void) {
        self.band = band
        self.commit = commit
        _initial = State(initialValue: initial)
        _value = State(initialValue: Double(initial))
    }

    var body: some View {
        HStack {
            Text(band)
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
            Slider(value: $value, in: -7...7, step: 1) { editing in
                // SwiftUI can report an end-of-edit with the value untouched;
                // skip it so a passive re-render doesn't write to the headset.
                if !editing { let v = Int(value.rounded()); if v != initial { commit(v) } }
            }
            Text(value > 0 ? "+\(Int(value))" : "\(Int(value))")
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
        .onAppear { value = Double(initial) }
        .onChange(of: initial) { _, newValue in
            // Adopt refreshes (e.g. switching EQ preset re-reads all bands).
            if Int(value.rounded()) != newValue { value = Double(newValue) }
        }
    }
}

/// A slider that shows `initial` until first drag, then tracks locally and
/// commits only when the user lets go.
private struct SliderRow: View {
    let label: String
    let commit: (Int) -> Void
    @State private var value: Double
    @State private var initial: Int

    init(label: String, initial: Int, commit: @escaping (Int) -> Void) {
        self.label = label
        self.commit = commit
        _initial = State(initialValue: initial)
        _value = State(initialValue: Double(initial))
    }

    var body: some View {
        HStack {
            Text(label).font(.callout)
            Slider(value: $value, in: 0...100, step: 1) { editing in
                // Skip end-of-edit notifications that arrive with the value
                // untouched — they'd fire a pointless HID write.
                if !editing { let v = Int(value.rounded()); if v != initial { commit(v) } }
            }
            Text("\(Int(value.rounded()))")
                .font(.caption.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
        .onAppear { value = Double(initial) }
        .onChange(of: initial) { _, newValue in
            // Adopt external refreshes (only when not mid-drag; SwiftUI's
            // onEditingChanged already committed any local edit).
            if Int(value.rounded()) != newValue { value = Double(newValue) }
        }
    }
}
