import SwiftUI
import UserNotifications

@main
struct A50DockSwitchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(state: state)
        } label: {
            Image(systemName: iconName)
            if let charge = state.charge {
                Text("\(charge)%")
            }
        }

        Window("A50 Dashboard", id: "dashboard") {
            DashboardView(state: state)
        }
        .defaultSize(width: 1080, height: 790)
    }

    private var iconName: String {
        switch state.state {
        case .undocked: return "headphones"
        case .docked, .off: return "speaker.wave.2"
        case .paused: return "pause.circle"
        case .error, .accConflict: return "exclamationmark.triangle"
        }
    }
}
