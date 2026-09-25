import AppKit
import ApplicationServices

enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Registers the app in the Input Monitoring list; macOS only lists apps that ask.
    static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    static func openAccessibilitySettings() {
        open(primary: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
             fallback: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open(primary: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
             fallback: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")
    }

    /// macOS sometimes keeps an Accessibility entry whose switch shows on
    /// while the grant belongs to an older build (the signature changed). Wipe
    /// Superkeys' entry, ask again so a fresh one appears, and open the list.
    static func resetAccessibility() {
        if let id = Bundle.main.bundleIdentifier {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", "Accessibility", id]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
        requestAccessibility()
        openAccessibilitySettings()
    }

    /// "Displays have separate Spaces" lives under Desktop & Dock → Mission Control.
    static func openDesktopAndDockSettings() {
        open(primary: "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
             fallback: "x-apple.systempreferences:com.apple.preference.dock")
    }

    private static func open(primary: String, fallback: String) {
        if let url = URL(string: primary), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: fallback) { NSWorkspace.shared.open(url) }
    }
}
