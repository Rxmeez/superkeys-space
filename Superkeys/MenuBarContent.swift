import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Text(statusLine)
        if !state.lastAction.isEmpty {
            Text(state.lastAction)
        }
        Divider()
        Toggle("Hyper and Meh Keys", isOn: Binding(
            get: { !state.paused },
            set: { state.setPaused(!$0) }
        ))
        switch state.status {
        case .needsAccess:
            Button("Grant Accessibility Access…") { Permissions.openAccessibilitySettings() }
        case .unavailable:
            Button("Restart Hyper and Meh Keys") { state.restart() }
        case .on, .paused:
            EmptyView()
        }
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Superkeys") {
            state.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch state.status {
        case .on: "Hyper and Meh keys are on"
        case .paused: "Paused. Caps Lock and right ⌘ work as normal"
        case .needsAccess: "Needs Accessibility access"
        case .unavailable: "Hyper and Meh keys couldn't start"
        }
    }
}
