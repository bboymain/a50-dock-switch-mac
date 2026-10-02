import SwiftUI

// MARK: - Card

/// A dashboard card: panel background, hairline border, the astro cut corner,
/// the 2px accent strip along the top, and a `// TITLE` heading.
struct Card<Content: View>: View {
    let theme: Theme
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    private var shape: NotchedRect { NotchedRect(notch: theme.notch, radius: theme.radius) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 0) {
                Text("// ").foregroundStyle(theme.accent)
                Text(title).foregroundStyle(theme.muted)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(theme.muted)
                }
            }
            .font(.system(size: 11, weight: .bold))
            .kerning(2.5)

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack(alignment: .top) {
                theme.panel
                LinearGradient(
                    stops: [.init(color: theme.accent, location: 0),
                            .init(color: theme.accent.opacity(0), location: 0.7)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 2)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Buttons

enum AstroButtonKind {
    case plain, primary, warn, on

    func colors(_ theme: Theme) -> (fill: Color, text: Color, border: Color) {
        switch self {
        case .plain:   return (.clear, theme.text, theme.line)
        case .primary: return (theme.accent, theme.accentContrast, theme.accent)
        case .warn:    return (.clear, theme.bad, theme.bad)
        case .on:      return (theme.ok, theme.accentContrast, theme.ok)
        }
    }
}

private struct PressFeedback: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct AstroButton: View {
    let theme: Theme
    let title: String
    var kind: AstroButtonKind = .plain
    var systemImage: String?
    var stretch = true
    var mini = false
    var disabled = false

    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let c = kind.colors(theme)
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: mini ? 10 : 12, weight: .bold))
            .kerning(mini ? 1 : 1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.vertical, mini ? 7 : 9)
            .padding(.horizontal, mini ? 12 : 16)
            .frame(maxWidth: stretch ? .infinity : nil)
            .foregroundStyle(hovering && kind == .plain ? theme.accent : c.text)
            .background(
                RoundedRectangle(cornerRadius: theme.radius)
                    .fill(hovering && kind == .plain ? theme.accent.opacity(0.08) : c.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius)
                    .stroke(hovering && kind != .plain ? theme.accent : c.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressFeedback())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
    }
}

/// The upstream's `.preset` chip — shared width, used for EQ presets and
/// noise-gate modes.
struct PresetButton: View {
    let theme: Theme
    let title: String
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .kerning(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.vertical, 9)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 18)
                .foregroundStyle(active ? theme.accentContrast : (hovering ? theme.text : theme.muted))
                .background(
                    RoundedRectangle(cornerRadius: theme.radius)
                        .fill(active ? theme.accent : theme.panel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius)
                        .stroke(active ? theme.accent : theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(PressFeedback())
        .onHover { hovering = $0 }
    }
}

// MARK: - Sliders

private func quantise(_ raw: Double, _ range: ClosedRange<Double>, _ step: Double) -> Double {
    guard step > 0 else { return raw }
    let snapped = (raw / step).rounded() * step
    return min(range.upperBound, max(range.lowerBound, snapped))
}

private func fraction(_ v: Double, _ range: ClosedRange<Double>) -> CGFloat {
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((v - range.lowerBound) / span)
}

/// The upstream uses native `<input type=range>` tinted with the accent colour.
/// SwiftUI won't restyle those, so the track and thumb are drawn to match. The
/// write is deferred to the end of the drag — see DashboardViewModel for why.
struct AstroSlider: View {
    let theme: Theme
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    /// Uppercase caption above the track; nil hides the header row.
    var header: String?
    var suffix: String = "%"
    let external: Int
    let commit: (Int) -> Void

    @State private var local: Double
    @State private var editing = false

    init(
        theme: Theme,
        range: ClosedRange<Double> = 0...100,
        step: Double = 1,
        header: String? = nil,
        suffix: String = "%",
        external: Int,
        commit: @escaping (Int) -> Void
    ) {
        self.theme = theme
        self.range = range
        self.step = step
        self.header = header
        self.suffix = suffix
        self.external = external
        self.commit = commit
        _local = State(initialValue: Double(external))
    }

    private func display(_ v: Int) -> String {
        if range.lowerBound < 0 {
            return "\(v > 0 ? "+" : "")\(v)"
        }
        return "\(v)\(suffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                HStack {
                    Text(header)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(theme.muted)
                    Spacer()
                    Text(display(Int(local.rounded())))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let inset: CGFloat = 8
                let travel = max(1, w - inset * 2)
                let thumbX = inset + fraction(local, range) * travel

                ZStack(alignment: .leading) {
                    Capsule().fill(theme.line).frame(height: 6)
                    Capsule().fill(theme.accent).frame(width: max(6, thumbX), height: 6)
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 16, height: 16)
                        .position(x: thumbX, y: geo.size.height / 2)
                }
                .frame(width: w, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            editing = true
                            let t = min(1, max(0, (g.location.x - inset) / travel))
                            let raw = range.lowerBound + Double(t) * (range.upperBound - range.lowerBound)
                            local = quantise(raw, range, step)
                        }
                        .onEnded { _ in
                            editing = false
                            let v = Int(local.rounded())
                            if v != external { commit(v) }
                        }
                )
            }
            .frame(height: 16)
        }
        .onAppear { local = Double(external) }
        .onChange(of: external) { _, newValue in
            // Adopt device refreshes, but never yank the track mid-drag.
            if !editing, Int(local.rounded()) != newValue { local = Double(newValue) }
        }
    }
}

/// Vertical variant for the EQ bands (the upstream rotates its range inputs
/// by -90 degrees).
struct VerticalSlider: View {
    let theme: Theme
    var range: ClosedRange<Double> = -7...7
    var step: Double = 1
    let external: Int
    let commit: (Int) -> Void

    @State private var local: Double
    @State private var editing = false

    init(theme: Theme, range: ClosedRange<Double> = -7...7, step: Double = 1,
         external: Int, commit: @escaping (Int) -> Void) {
        self.theme = theme
        self.range = range
        self.step = step
        self.external = external
        self.commit = commit
        _local = State(initialValue: Double(external))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let inset: CGFloat = 8
            let travel = max(1, h - inset * 2)
            let thumbY = h - inset - fraction(local, range) * travel
            let fillHeight = max(0, h - thumbY)

            ZStack(alignment: .top) {
                Capsule().fill(theme.line).frame(width: 6)
                VStack {
                    Spacer()
                    Capsule().fill(theme.accent).frame(width: 6, height: fillHeight)
                }
                .frame(height: h)
                Circle()
                    .fill(theme.accent)
                    .frame(width: 16, height: 16)
                    .position(x: w / 2, y: thumbY)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        editing = true
                        let t = min(1, max(0, (h - inset - g.location.y) / travel))
                        let raw = range.lowerBound + Double(t) * (range.upperBound - range.lowerBound)
                        local = quantise(raw, range, step)
                    }
                    .onEnded { _ in
                        editing = false
                        let v = Int(local.rounded())
                        if v != external { commit(v) }
                    }
            )
        }
        .onAppear { local = Double(external) }
        .onChange(of: external) { _, newValue in
            if !editing, Int(local.rounded()) != newValue { local = Double(newValue) }
        }
    }
}

/// Upstream's dark `<select>`. SwiftUI's menu picker keeps macOS's blue chrome,
/// which clashes with every theme, so the control is drawn to match instead.
struct DeviceMenu: View {
    let theme: Theme
    let devices: [AudioOutputDevice]
    let selection: String      // selected UID, "" when unset
    let placeholder: String    // name shown while unset
    let onSelect: (String) -> Void

    @State private var hovering = false

    private var currentName: String {
        if !selection.isEmpty, let d = devices.first(where: { $0.uid == selection }) {
            return d.name
        }
        return placeholder.isEmpty ? "—" : placeholder
    }

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button(device.name) { onSelect(device.uid) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(theme.panel2)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius)
                    .stroke(hovering ? theme.accent : theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.radius))
        }
        // `.borderlessButton` reorders the indicator and drops the label's
        // background; the default style keeps the drawn box and just hides the
        // system chevron.
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
    }
}

// MARK: - Header parts

/// The `A50` badge in the brand lockup — accent square with the bottom-right
/// corner clipped, as in `.brand .logo`.
struct BrandSquare: View {
    let theme: Theme
    var side: CGFloat = 44

    var body: some View {
        Text("A50")
            .font(.system(size: 14, weight: .black))
            .kerning(1)
            .foregroundStyle(theme.accentContrast)
            .frame(width: side, height: side)
            .background(theme.accent)
            .clipShape(BrandCut())
    }
}

private struct BrandCut: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = rect.width * 0.28
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Upstream's `.state-pill`: hairline box, glowing dot, 11px tracked label.
struct StatePill: View {
    let theme: Theme
    let display: StateDisplay

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(display.dot ?? theme.muted)
                .frame(width: 9, height: 9)
                .shadow(color: display.dot ?? .clear, radius: 4)
            Text(display.pill)
                .font(.system(size: 11, weight: .black))
                .kerning(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.line, lineWidth: 1))
    }
}

/// Upstream's `.bat-chip`: percentage plus four skewed segments, each worth 25%.
struct BatteryChip: View {
    let theme: Theme
    let charge: Int?
    let charging: Bool

    @State private var dimmed = false

    private var low: Bool { (charge ?? 100) <= 15 }

    var body: some View {
        HStack(spacing: 12) {
            Text(charge.map { "\($0)%" } ?? "--%")
                .font(.system(size: 14, weight: .heavy))
                .kerning(1)
                .monospacedDigit()
                .foregroundStyle(low ? theme.bad : theme.muted)

            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { i in
                    segment(index: i)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .background(theme.bg)
        .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.line, lineWidth: 1))
        .opacity(charging && dimmed ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: charging && dimmed)
        .onAppear { dimmed = charging }
        .onChange(of: charging) { _, c in dimmed = c }
    }

    private func segment(index: Int) -> some View {
        // Same maths as the web UI: `width = clamp((v - i * 25) * 4, 0..100)%`,
        // i.e. each segment owns a 25-point slice of the charge.
        let v = Double(charge ?? 0)
        let portion = min(1, max(0, (v - Double(index) * 25) / 25))
        let width = CGFloat(portion) * 24

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(theme.line)
            RoundedRectangle(cornerRadius: 2)
                .fill(low ? theme.bad : theme.accent)
                .frame(width: width)
        }
        .frame(width: 24, height: 13)
        // `skewX(-18deg)` from the stylesheet: x' = x + tan(θ)·y. There is no
        // skew modifier (or convenience initialiser) in SwiftUI/CoreGraphics,
        // so lean the drawn frame rather than the layout.
        .transformEffect(
            CGAffineTransform(a: 1, b: 0, c: tan(-18 * .pi / 180), d: 1, tx: 0, ty: 0)
        )
    }
}
