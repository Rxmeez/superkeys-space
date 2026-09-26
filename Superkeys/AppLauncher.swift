import AppKit

@MainActor
enum AppLauncher {
    static func launch(keyCode: Int, then second: Int? = nil) {
        guard let app = BindingsStore.shared.app(forKeyCode: keyCode, then: second) else { return }
        launch(app)
    }

    static func launch(_ app: BoundApp) {
        // Its key again while it's in front: the next of its windows. With
        // one window or none, open it as usual (which reopens a closed one).
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == app.bundleID,
           WindowManager.shared.cycleWindows(of: front) {
            return
        }
        guard let url = applicationURL(for: app) else {
            AppState.shared.lastAction = "Could not open \(app.name)"
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            Task { @MainActor in
                AppState.shared.lastAction = error == nil ? app.name : "Could not open \(app.name)"
            }
        }
    }

    private static func applicationURL(for app: BoundApp) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            return url
        }
        let fm = FileManager.default
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            let path = "\(dir)/\(app.name).app"
            if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}
