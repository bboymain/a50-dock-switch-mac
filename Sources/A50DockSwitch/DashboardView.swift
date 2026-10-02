import SwiftUI
import A50HID

/// Headset control dashboard: EQ preset + per-band gains, sidetone, mic level,
/// noise gate, game/voice balance. Mirrors the controls in the Windows app.
struct DashboardView: View {
    @StateObject private var vm: DashboardViewModel

    init(state: AppState) {
        _vm = StateObject(wrappedValue: DashboardViewModel(hid: state.hid))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let s = vm.settings {
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
                    .lineLimit(2)
            }

            Button("Refresh") { vm.refresh() }
                .keyboardShortcut("r")
        }
        .padding(18)
        .frame(width: 420)
        .task { vm.refresh() }
    }

    private var header: some View {
        HStack {
            Label("A50 Headset Settings", systemImage: "slider.horizontal.3")
                .font(.headline)
            Spacer()
            if vm.loading { ProgressView().controlSize(.small) }
        }
    }

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
                        Text("\(p). \(s.eqNames.indices.contains(p - 1) ? s.eqNames[p - 1] : "PRESET \(p)")")
                            .tag(p)
                    }
                }
                .pickerStyle(.segmented)

                let bands = ["480", "1K", "4.8K", "8K", "16K"]
                ForEach(0..<5, id: \.self) { i in
                    let gain = s.eqGains.indices.contains(i) ? s.eqGains[i] : 0
                    HStack {
                        Text(bands[i])
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                        Slider(
                            value: Binding(
                                get: { Double(gain) },
                                set: { vm.setEqGain(i, Int($0.rounded())) }
                            ),
                            in: -7...7,
                            step: 1
                        )
                        Text(gain > 0 ? "+\(gain)" : "\(gain)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Text("dB — drag a slider; it writes on release.")
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
        GroupBox("Game / Voice Balance") {
            HStack {
                Text("Voice").font(.caption)
                Slider(value: .constant(Double(s.balance) / 255.0), in: 0...1)
                    .disabled(true)
                Text("Game").font(.caption)
                Text("\(s.balance)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(4)
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
                if !editing { commit(Int(value.rounded())) }
            }
            Text("\(Int(value.rounded()))")
                .font(.caption.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
        .onAppear { value = Double(initial) }
        .onChange(of: initial) { newValue in
            // Adopt external refreshes (only when not mid-drag; SwiftUI's
            // onEditingChanged already committed any local edit).
            if Int(value.rounded()) != newValue { value = Double(newValue) }
        }
    }
}
