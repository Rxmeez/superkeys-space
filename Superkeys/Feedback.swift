import AppKit

/// Opens the repository's issue forms with what's known filled in: versions,
/// the Mac, and a diagnostics summary. Never the bindings or anything typed.
@MainActor
enum Feedback {
    enum Kind { case feature, problem }

    static let repository = URL(string: "https://github.com/Rxmeez/superkeys-space")!
    static let sponsor = URL(string: "https://github.com/sponsors/Rxmeez")!

    static func open(_ kind: Kind) {
        NSWorkspace.shared.open(url(kind))
    }

    static func url(_ kind: Kind) -> URL {
        var parts = URLComponents(url: repository.appendingPathComponent("issues/new"),
                                  resolvingAgainstBaseURL: false)!
        let os = ProcessInfo.processInfo.operatingSystemVersion
        switch kind {
        case .feature:
            parts.queryItems = [
                URLQueryItem(name: "template", value: "feature.yml"),
                URLQueryItem(name: "version", value: Updater.version),
            ]
        case .problem:
            parts.queryItems = [
                URLQueryItem(name: "template", value: "bug.yml"),
                URLQueryItem(name: "version", value: Updater.version),
                URLQueryItem(name: "macos", value: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
                URLQueryItem(name: "mac", value: mac),
                URLQueryItem(name: "diagnostics", value: diagnostics()),
            ]
        }
        return parts.url!
    }

    private static var mac: String {
        [sysctl("hw.model"), sysctl("machdep.cpu.brand_string")].compactMap { $0 }.joined(separator: ", ")
    }

    /// Key tools that also remap Caps Lock or right ⌘, or watch the keyboard.
    private static let otherKeyTools = [
        "org.pqrs.Karabiner-Elements.Settings": "Karabiner-Elements",
        "org.pqrs.Karabiner-Menu": "Karabiner-Elements",
        "org.pqrs.Karabiner-NotificationWindow": "Karabiner-Elements",
        "com.knollsoft.Hyperkey": "Hyperkey",
        "com.hegenberg.BetterTouchTool": "BetterTouchTool",
        "com.raycast.macos": "Raycast",
    ]

    /// A plain-text summary for problem reports: state, counts and versions.
    /// Never which keys are bound, to which apps, or anything typed.
    static func diagnostics() -> String {
        let state = AppState.shared
        let bindings = BindingsStore.shared
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let status: String = switch state.status {
        case .on: "on"
        case .paused: "paused"
        case .needsAccess: "needs Accessibility access"
        case .unavailable: "couldn't start"
        }
        let groups = (bindings.bindings.map(\.keyCode2) + bindings.keystrokes.map(\.keyCode2))
            .compactMap { $0 }.count
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let tools = Set(otherKeyTools.filter { running.contains($0.key) }.values).sorted()
        let problems = ConfigSync.shared.problems
        return [
            "Superkeys \(Updater.version) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(mac)",
            "Keys: \(status); Accessibility \(Permissions.isTrusted ? "granted" : "not granted"); remap \(HIDRemap.isInstalled ? "installed" : "not installed")",
            "Keyboards: \(HIDRemap.keyboardNames().joined(separator: ", "))",
            "Displays: \(NSScreen.screens.count)\(state.multipleDisplays ? (state.separateSpaces ? ", separate desktops" : ", shared desktops") : ""); desktop shortcuts \(state.desktopShortcutsEnabled ? "on" : "off"); numbering \(SpaceManager.numbering.rawValue)",
            "App keys: \(bindings.bindings.count); keystrokes: \(bindings.keystrokes.count); groups: \(groups)",
            "Config: \(problems.isEmpty ? "ok" : "\(problems.count) problem\(problems.count == 1 ? "" : "s")\(ConfigSync.shared.notApplied ? ", not applied" : "")")",
            "Chord panel \(state.showCheatSheet ? "on" : "off"); open at login \(state.launchAtLogin ? "on" : "off")",
            "Other key tools running: \(tools.isEmpty ? "none" : tools.joined(separator: ", "))",
        ].joined(separator: "\n")
    }

    static func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics(), forType: .string)
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}
