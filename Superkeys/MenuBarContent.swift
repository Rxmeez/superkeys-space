import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Text("Superkeys \(Updater.version)")
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
            Button("Reset Accessibility Access…") { Permissions.resetAccessibility() }
        case .unavailable:
            Button("Restart Hyper and Meh Keys") { state.restart() }
        case .on, .paused:
            EmptyView()
        }
        Divider()
        if Updater.isEnabled {
            Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
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
