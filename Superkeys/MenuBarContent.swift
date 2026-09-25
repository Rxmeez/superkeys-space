import SwiftUI

/// Kept short: the on/off switch, a fix when something's wrong, and the way
/// into Settings, which has everything else (version and updates, the tour,
/// Reset Access).
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        switch state.status {
        case .needsAccess:
            Text("Needs Accessibility access")
            Button("Grant Accessibility Access…") { Permissions.openAccessibilitySettings() }
            Divider()
        case .unavailable:
            Text("Hyper and Meh keys couldn't start")
            Button("Restart Hyper and Meh Keys") { state.restart() }
            Divider()
        case .on, .paused:
            EmptyView()
        }
        Toggle("Hyper and Meh Keys", isOn: Binding(
            get: { !state.paused },
            set: { state.setPaused(!$0) }
        ))
        Divider()
        if let version = WhatsNew.pending {
            Button("What's New in \(version)") { WhatsNew.show() }
        }
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit Superkeys") {
            state.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
