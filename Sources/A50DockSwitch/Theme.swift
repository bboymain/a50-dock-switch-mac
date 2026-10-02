import SwiftUI

/// Colour and shape tokens lifted from the upstream dashboard's `style.css`
/// (`/bboymain/a50-dock-switch/dashboard`) so the native panel reads the same
/// as the web UI. Three themes are offered, matching the app's theme picker.
struct Theme: Equatable {
    let id: String
    let name: String

    let bg: Color
    let bg2: Color
    let panel: Color
    let panel2: Color
    let line: Color

    let accent: Color
    let accent2: Color
    let accentContrast: Color

    let text: Color
    let muted: Color
    let ok: Color
    let bad: Color
    let blue: Color

    /// `--radius`
    let radius: CGFloat
    /// `--clip`: the astro theme cuts the top-right corner of every card.
    let notch: CGFloat

    static let astro = Theme(
        id: "astro", name: "ASTRO ORANGE",
        bg: rgb(0x000000), bg2: rgb(0x0a0a0a),
        panel: rgb(0x111111), panel2: rgb(0x181818), line: rgb(0x262626),
        accent: rgb(0xff6a00), accent2: rgb(0xff9438), accentContrast: rgb(0x0b0b0b),
        text: rgb(0xececec), muted: rgb(0x8f8f8f),
        ok: rgb(0x3ec46d), bad: rgb(0xff4d4d), blue: rgb(0x4a9eff),
        radius: 4, notch: 16
    )

    static let neon = Theme(
        id: "neon", name: "NEON GLASS",
        bg: rgb(0x07070f), bg2: rgb(0x0a0a16),
        panel: rgb(0x14142a, alpha: 0.72), panel2: rgb(0x1c1c38, alpha: 0.8),
        line: rgb(0x8ca0ff, alpha: 0.16),
        accent: rgb(0x00e5ff), accent2: rgb(0xa855f7), accentContrast: rgb(0x05050d),
        text: rgb(0xeaf7ff), muted: rgb(0x7f8db3),
        ok: rgb(0x3dffb0), bad: rgb(0xff4d8d), blue: rgb(0x00e5ff),
        radius: 14, notch: 0
    )

    static let minimal = Theme(
        id: "minimal", name: "MINIMAL DARK",
        bg: rgb(0x101014), bg2: rgb(0x131317),
        panel: rgb(0x17171b), panel2: rgb(0x1c1c21), line: rgb(0x26262c),
        accent: rgb(0x7c9cff), accent2: rgb(0x9db4ff), accentContrast: rgb(0x101014),
        text: rgb(0xe8e8ec), muted: rgb(0x8b8b93),
        ok: rgb(0x5ac88a), bad: rgb(0xe06a6a), blue: rgb(0x7c9cff),
        radius: 12, notch: 0
    )

    static let all = [astro, neon, minimal]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .astro
    }
}

/// User-interface preference only, so it lives in UserDefaults rather than
/// `AppConfig` — adding a field there would break decoding of existing configs.
enum ThemeStore {
    private static let key = "theme"
    static var current: String {
        get { UserDefaults.standard.string(forKey: key) ?? Theme.astro.id }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

private func rgb(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(
        red: Double((hex >> 16) & 0xff) / 255,
        green: Double((hex >> 8) & 0xff) / 255,
        blue: Double(hex & 0xff) / 255,
        opacity: alpha
    )
}

/// Reproduces `clip-path: polygon(0 0, calc(100% - 16px) 0, 100% 16px, 100% 100%, 0 100%)`
/// from the astro theme, falling back to a rounded rect for themes with `notch == 0`.
struct NotchedRect: Shape {
    var notch: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard notch > 0 else {
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
            return p
        }
        let n = min(notch, min(rect.width, rect.height))
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + n))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The upstream maps dock state to a pill label, a large hero word and a dot
/// colour (`dashboard/app.js: refreshStatus`). Keeping that mapping verbatim is
/// what makes the panel recognisable next to the original.
struct StateDisplay: Equatable {
    let pill: String
    let big: String
    let dot: Color?

    init(_ state: DockState, theme: Theme) {
        switch state {
        case .undocked:
            pill = "HEADPHONES ACTIVE"; big = "HEADPHONES"; dot = theme.blue
        case .docked:
            pill = "DOCKED — SPEAKERS"; big = "SPEAKERS"; dot = theme.ok
        case .off:
            pill = "HEADSET OFF — SPEAKERS"; big = "SPEAKERS"; dot = theme.ok
        case .paused:
            pill = "AUTOMATION PAUSED"; big = "PAUSED"; dot = theme.muted
        case .error:
            pill = "BASE STATION NOT FOUND"; big = "NO BASE"; dot = theme.bad
        case .accConflict:
            pill = "ASTRO CC RUNNING"; big = "NO BASE"; dot = theme.bad
        }
    }
}
