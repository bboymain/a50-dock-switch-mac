import SwiftUI
import AppKit
import os
import A50HID

private let log = Logger(subsystem: "com.a50.dockswitch", category: "dashboard")

/// The Astro A50 headset art shipped with the upstream project.
enum BrandAsset {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()
}

/// Native port of the upstream dashboard (`bboymain/a50-dock-switch/dashboard`):
/// same theme tokens, card grid, headings and state wording, with only the
/// controls macOS and the hardware actually support.
struct DashboardView: View {
    @ObservedObject var state: AppState
    @StateObject private var vm: DashboardViewModel
    @State private var tab: Tab = .dashboard

    enum Tab { case dashboard, settings }

    init(state: AppState) {
        log.debug("DashboardView created (new StateObject wrapper)")
        self.state = state
        _vm = StateObject(wrappedValue: DashboardViewModel(hid: state.hid))
    }

    private var theme: Theme { Theme.named(state.themeName) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.line).frame(height: 1)

            if let s = vm.settings, s.hasUnsavedChanges || vm.saving {
                storageBanner(s)
            }

            Group {
                switch tab {
                case .dashboard: dashboardTab
                case .settings: settingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)   // keeps native pickers/fields on-palette
        .task { vm.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            // Hand the app back to accessory once the dashboard closes, so it
            // stops occupying a Dock slot. Promotion happens in MenuBarContent.
            if let window = note.object as? NSWindow, window.title == "A50 Dashboard" {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 13) {
                BrandSquare(theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMMAND CENTER")
                        .font(.system(size: 16, weight: .black))
                        .kerning(3.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(theme.text)
                    Text("// A50 DOCK SWITCH AUTOMATION")
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(2.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(theme.accent)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                tabButton("DASHBOARD", .dashboard)
                tabButton("SETTINGS", .settings)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                // Both hold their ideal width: an HStack otherwise squeezes
                // whichever child can shrink, which truncated the state pill.
                BatteryChip(theme: theme, charge: state.charge, charging: state.charging)
                    .fixedSize()
                StatePill(theme: theme, display: StateDisplay(state.state, theme: theme))
                    .fixedSize()
                themePicker.fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [theme.bg2, theme.bg], startPoint: .top, endPoint: .bottom)
        )
    }

    private func tabButton(_ title: String, _ target: Tab) -> some View {
        let active = tab == target
        return Button {
            tab = target
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .kerning(2.5)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(active ? theme.accent : theme.muted)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(active ? theme.accent : .clear)
                        .frame(height: 3)
                }
        }
        .buttonStyle(.plain)
    }

    private var themePicker: some View {
        Menu {
            ForEach(Theme.all, id: \.id) { t in
                Button {
                    state.setTheme(t.id)
                } label: {
                    if t.id == state.themeName {
                        Label(t.name, systemImage: "checkmark")
                    } else {
                        Text(t.name)
                    }
                }
            }
        } label: {
            Text(Theme.named(state.themeName).name)
                .font(.system(size: 10, weight: .bold))
                .kerning(1)
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.line, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func storageBanner(_ s: AstroHID.HeadsetSettings) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vm.saving ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                .foregroundStyle(theme.accent)
            Text(vm.saving
                 ? "WRITING TO THE HEADSET…"
                 : "\(s.eqGains.filter { $0 != 0 }.count) EQ BANDS + MIC SETTINGS NOT STORED ON THE HEADSET")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(theme.accent)
            Spacer()
            AstroButton(
                theme: theme,
                title: vm.saving ? "SAVING…" : "SAVE TO HEADSET",
                kind: .primary,
                stretch: false,
                disabled: vm.saving,
                action: vm.save
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(theme.accent.opacity(0.10))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    // MARK: - Dashboard tab

    private var dashboardTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let s = vm.settings {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                        spacing: 14
                    ) {
                        Card(theme: theme, title: "ASTRO A50 GEN 4") {
                            HeroContent(state: state, settings: s, theme: theme)
                        }
                        .frame(height: 272)

                        Card(theme: theme, title: "EQUALIZER") {
                            EqualizerContent(settings: s, theme: theme, vm: vm)
                        }
                        .frame(height: 272)

                        Card(theme: theme, title: "MICROPHONE") {
                            MicrophoneContent(settings: s, theme: theme, vm: vm)
                        }
                        .frame(height: 272)

                        Card(theme: theme, title: "GAME : VOICE MIX") {
                            MixContent(settings: s, theme: theme)
                        }
                        .frame(height: 214)

                        Card(theme: theme, title: "AUDIO ROUTING") {
                            RoutingContent(state: state, theme: theme)
                        }
                        .frame(height: 214)

                        Card(theme: theme, title: "MANUAL CONTROL") {
                            ManualContent(state: state, theme: theme)
                        }
                        .frame(height: 214)
                    }

                    // Full width: kept outside the grid rather than relying on
                    // gridCellColumns, which the storage card ignored.
                    Card(theme: theme, title: "HEADSET STORAGE") {
                        StorageContent(settings: s, vm: vm, theme: theme)
                    }
                    .frame(height: 128)
                } else if vm.loading {
                    ProgressView("Reading headset settings…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                if let err = vm.lastError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Settings tab

    private var settingsTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                    spacing: 14
                ) {
                    Card(theme: theme, title: "SETTINGS") {
                        SettingsContent(state: state, theme: theme)
                    }
                    .frame(height: 260)

                    Card(theme: theme, title: "ABOUT") {
                        AboutContent(theme: theme)
                    }
                    .frame(height: 260)
                    .gridCellColumns(2)
                }

                Card(theme: theme, title: "EVENT HISTORY") {
                    HistoryContent(state: state, theme: theme)
                }
                .frame(height: 300)
            }
            .padding(20)
        }
    }
}

// MARK: - Card contents

private struct HeroContent: View {
    @ObservedObject var state: AppState
    let settings: AstroHID.HeadsetSettings
    let theme: Theme

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let img = BrandAsset.image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    BrandSquare(theme: theme, side: 78)
                }
            }
            .frame(height: 96)
            .shadow(color: theme.accent.opacity(0.45), radius: 18)

            Text(StateDisplay(state.state, theme: theme).big)
                .font(.system(size: 22, weight: .black))
                .kerning(2)
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity)

            if state.accRunning {
                Text("ASTRO COMMAND CENTER IS RUNNING — CLOSE IT")
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(theme.bad)
                    .multilineTextAlignment(.center)
            }

            meta(baseStation)
            meta(balance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var baseStation: AttributedString {
        var s = AttributedString("base station: ")
        s.foregroundColor = theme.muted
        var v = AttributedString(state.state == .error || state.state == .accConflict ? "NOT FOUND" : "ONLINE")
        v.foregroundColor = theme.text
        v.inlinePresentationIntent = .stronglyEmphasized
        s.append(v)
        return s
    }

    private var balance: AttributedString {
        var s = AttributedString("game:voice balance: ")
        s.foregroundColor = theme.muted
        var v = AttributedString("GAME \(settings.gamePercent)% : VOICE \(100 - settings.gamePercent)%")
        v.foregroundColor = theme.text
        v.inlinePresentationIntent = .stronglyEmphasized
        s.append(v)
        return s
    }

    private func meta(_ text: AttributedString) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

private struct EqualizerContent: View {
    let settings: AstroHID.HeadsetSettings
    let theme: Theme
    let vm: DashboardViewModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { preset in
                    PresetButton(
                        theme: theme,
                        title: presetName(preset),
                        active: settings.eqPreset == preset
                    ) { vm.setEqPreset(preset) }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                VStack {
                    Text("+7")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("-7")
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.muted)
                .frame(height: 136)

                ForEach(0..<5, id: \.self) { i in
                    VStack(spacing: 5) {
                        VerticalSlider(
                            theme: theme,
                            external: settings.eqGains.indices.contains(i) ? settings.eqGains[i] : 0
                        ) { vm.setEqGain(i, $0) }
                        .frame(height: 136)

                        Text("BAND \(i + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .kerning(1)
                            .foregroundStyle(theme.muted)
                        Text(bandFrequency(i))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(theme.muted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("dB — each band writes when you release it.")
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func presetName(_ preset: Int) -> String {
        let name = settings.eqNames.indices.contains(preset - 1) ? settings.eqNames[preset - 1] : ""
        return name.uppercased().hasPrefix("PRESET") ? "PRESET \(preset)" : name.uppercased()
    }

    /// Bands are not evenly spaced, so the frequency comes from `0x70` rather
    /// than being assumed.
    private func bandFrequency(_ index: Int) -> String {
        guard settings.eqFreqs.indices.contains(index), settings.eqFreqs[index] > 0 else {
            return "—"
        }
        let f = settings.eqFreqs[index]
        return f >= 1000 ? String(format: "%.1f kHz", Double(f) / 1000) : "\(f) Hz"
    }
}

private struct MicrophoneContent: View {
    let settings: AstroHID.HeadsetSettings
    let theme: Theme
    let vm: DashboardViewModel

    var body: some View {
        VStack(spacing: 9) {
            block {
                AstroSlider(
                    theme: theme,
                    header: "SIDETONE (HEAR YOURSELF)",
                    external: settings.sidetoneActive,
                    commit: vm.setSidetone
                )
            }

            block {
                AstroSlider(
                    theme: theme,
                    header: "MIC LEVEL",
                    external: settings.micActive,
                    commit: vm.setMic
                )
            }

            HStack(spacing: 8) {
                ForEach(AstroHID.NoiseGate.allCases, id: \.rawValue) { mode in
                    PresetButton(
                        theme: theme,
                        title: mode.label.uppercased(),
                        active: settings.noiseGate == mode.rawValue
                    ) { vm.setNoiseGate(mode.rawValue) }
                }
            }

            Text("Noise gate is stored on the headset after a save.")
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel2)
            .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius))
    }
}

private struct MixContent: View {
    let settings: AstroHID.HeadsetSettings
    let theme: Theme

    var body: some View {
        VStack(spacing: 9) {
            VStack(spacing: 7) {
                HStack {
                    Text("GAME : VOICE MIX")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(theme.muted)
                    Spacer()
                    Text("GAME \(settings.gamePercent)% : VOICE \(100 - settings.gamePercent)%")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.line)
                        Capsule().fill(theme.accent)
                            .frame(width: geo.size.width * CGFloat(settings.gamePercent) / 100)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("VOICE")
                    Spacer()
                    Text("GAME")
                }
                .font(.system(size: 9, weight: .bold))
                .kerning(1)
                .foregroundStyle(theme.muted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel2)
            .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius))

            Text("Moved with the buttons on the headset. The base station's default is \(settings.defaultGamePercent)% game.")
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text("Upstream's GAME/VOICE OUTPUT sliders control device volume — macOS exposes no volume property on the A50 endpoints, so they can't be ported.")
                .font(.system(size: 10))
                .foregroundStyle(theme.muted.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RoutingContent: View {
    @ObservedObject var state: AppState
    let theme: Theme

    var body: some View {
        VStack(spacing: 9) {
            row("WHEN DOCKED — SWITCH TO",
                selection: state.config.dockedUID,
                placeholder: state.config.dockedName) { uid in
                if let d = state.devices.first(where: { $0.uid == uid }) { state.setDockedDevice(d) }
            }

            row("WHEN UNDOCKED — SWITCH TO",
                selection: state.config.undockedUID,
                placeholder: state.config.undockedName) { uid in
                if let d = state.devices.first(where: { $0.uid == uid }) { state.setUndockedDevice(d) }
            }

            HStack {
                Text("Applied immediately — the config file is rewritten on change.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                Spacer()
                AstroButton(theme: theme, title: "REFRESH", stretch: false, mini: true) {
                    state.refreshDevices()
                }
            }
        }
    }

    private func row(
        _ label: String,
        selection: String,
        placeholder: String,
        changed: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(theme.muted)

            DeviceMenu(
                theme: theme,
                devices: state.devices,
                selection: selection,
                placeholder: placeholder,
                onSelect: changed
            )
        }
    }
}

private struct ManualContent: View {
    @ObservedObject var state: AppState
    let theme: Theme

    private var paused: Bool { state.config.paused }

    var body: some View {
        VStack(spacing: 10) {
            AstroButton(
                theme: theme,
                title: "SWITCH TO HEADPHONES",
                kind: .primary,
                systemImage: "headphones",
                disabled: state.config.undockedUID.isEmpty
            ) {
                state.manualSwitch(uid: state.config.undockedUID)
            }

            AstroButton(
                theme: theme,
                title: "SWITCH TO SPEAKERS",
                systemImage: "speaker.wave.2",
                disabled: state.config.dockedUID.isEmpty
            ) {
                state.manualSwitch(uid: state.config.dockedUID)
            }

            AstroButton(
                theme: theme,
                title: paused ? "RESUME AUTOMATION" : "PAUSE AUTOMATION",
                kind: paused ? .on : .warn,
                systemImage: paused ? "play.fill" : "pause.fill",
                action: state.togglePause
            )

            Text(attributedDefault)
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var attributedDefault: AttributedString {
        var s = AttributedString("current default: ")
        s.foregroundColor = theme.muted
        var v = AttributedString(state.defaultDeviceName.isEmpty ? "--" : state.defaultDeviceName)
        v.foregroundColor = theme.text
        v.inlinePresentationIntent = .stronglyEmphasized
        s.append(v)
        return s
    }
}

private struct StorageContent: View {
    let settings: AstroHID.HeadsetSettings
    let vm: DashboardViewModel
    let theme: Theme

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if settings.hasUnsavedChanges {
                    Text("Your EQ, sidetone, mic and noise-gate changes are only in the base station's working copy.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)
                    Text("SAVE TO HEADSET stores them — without it they are gone when the base station powers off.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.muted)
                } else {
                    Text("All settings are stored on the headset.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.ok)
                    if let notice = vm.notice {
                        Text(notice.uppercased())
                            .font(.system(size: 11))
                            .kerning(1)
                            .foregroundStyle(theme.ok.opacity(0.8))
                    }
                }

                Text("VOLUME MEMORY is not available: macOS exposes no volume property on the A50 Game/Voice endpoints, so per-device levels can't be remembered.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.muted.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                AstroButton(
                    theme: theme,
                    title: vm.saving ? "SAVING…" : "SAVE TO HEADSET",
                    kind: .primary,
                    stretch: false,
                    disabled: vm.saving || !settings.hasUnsavedChanges,
                    action: vm.save
                )
                AstroButton(theme: theme, title: "REFRESH", stretch: false, mini: true) {
                    vm.refresh()
                }
            }
        }
    }
}

private struct SettingsContent: View {
    @ObservedObject var state: AppState
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                field("POLL EVERY (SEC, 0 = FASTEST)",
                      value: Binding(
                        get: { state.config.interval },
                        set: { state.setPollInterval($0) }
                      ))
                field("CONFIRM AFTER (READS)",
                      value: Binding(
                        get: { Double(state.config.debounce) },
                        set: { state.setDebounce(Int($0.rounded())) }
                      ))
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { state.config.notifications },
                    set: { _ in state.toggleNotifications() }
                )) {
                    Text("SWITCH NOTIFICATIONS")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(theme.muted)
                }
                .toggleStyle(.checkbox)
                .tint(theme.accent)

                Toggle(isOn: Binding(
                    get: { state.loginItemEnabled },
                    set: { state.setLoginItem($0) }
                )) {
                    Text("START AT LOGIN")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(theme.muted)
                }
                .toggleStyle(.checkbox)
                .tint(theme.accent)
            }

            Text("Polling runs whether or not this window is open.")
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)

            Spacer(minLength: 0)
        }
    }

    private func field(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .kerning(1)
                .foregroundStyle(theme.muted)
            Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 90)
                .padding(.vertical, 6)
                .background(theme.panel2)
                .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius))
        }
    }
}

private struct HistoryContent: View {
    @ObservedObject var state: AppState
    let theme: Theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                if state.history.isEmpty {
                    Text("No events yet — dock and undock the headset to populate this list.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(state.history) { entry in
                        HStack(spacing: 12) {
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.muted)
                            Text(entry.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.text)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }
}

private struct AboutContent: View {
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Group {
                if let img = BrandAsset.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                } else {
                    BrandSquare(theme: theme, side: 70)
                }
            }
            .frame(width: 76, height: 96)
            .shadow(color: theme.accent.opacity(0.35), radius: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("AUTOMATED AUDIO, BECAUSE THE WINDOWS MIXER GOT OLD FAST.")
                    .font(.system(size: 12, weight: .black))
                    .kerning(1)
                    .foregroundStyle(theme.text)

                Text("Dock the headset — it's speakers. Undock it — it's headphones. Native macOS port of the upstream project, with the headset settings panel on top of it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Link(destination: URL(string: "https://github.com/bboymain/a50-dock-switch")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.accent)
                    }
                    Text("A50 DOCK SWITCH · MACOS")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
