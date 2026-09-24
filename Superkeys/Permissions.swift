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

    private static func open(primary: String, fallback: String) {
        if let url = URL(string: primary), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: fallback) { NSWorkspace.shared.open(url) }
    }
}
