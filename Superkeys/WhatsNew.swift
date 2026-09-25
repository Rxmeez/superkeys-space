import AppKit

/// After Superkeys updates itself, the menu offers "What's New in x.y.z"
/// until it's opened once. The notes are the ones Sparkle showed, from the
/// release's page on superkeys.space.
@MainActor
enum WhatsNew {
    private static let lastLaunchedKey = "lastLaunchedVersion"
    private static let pendingKey = "whatsNewVersion"

    /// The version whose notes haven't been seen yet, if it's the one running.
    static var pending: String? {
        let version = currentVersion
        return UserDefaults.standard.string(forKey: pendingKey) == version ? version : nil
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Call once at launch: a version change since the last launch means an
    /// update was installed.
    static func noteLaunch() {
        let defaults = UserDefaults.standard
        let version = currentVersion
        if let last = defaults.string(forKey: lastLaunchedKey), last != version {
            defaults.set(version, forKey: pendingKey)
        }
        defaults.set(version, forKey: lastLaunchedKey)
    }

    static func show() {
        guard let version = pending else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        AppState.shared.objectWillChange.send()
        let url = URL(string: "https://superkeys.space/download/Superkeys-\(version).html")!
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let notes = attributed(data) else {
                NSWorkspace.shared.open(url)
                return
            }
            present(version: version, notes: notes)
        }
    }

    private static func attributed(_ html: Data) -> NSAttributedString? {
        let styled = """
        <style>body{font:13px -apple-system;color:\(NSColor.labelColor.hexString)}h3{font-size:13px;margin:10px 0 4px}ul{margin:0;padding-left:18px}li{margin:3px 0}</style>
        """.data(using: .utf8)! + html
        return NSAttributedString(html: styled, documentAttributes: nil)
    }

    private static func present(version: String, notes: NSAttributedString) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "What's New in Superkeys \(version)"
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 10))
        text.textStorage?.setAttributedString(notes)
        text.isEditable = false
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.sizeToFit()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: min(260, max(60, text.frame.height + 8))))
        scroll.documentView = text
        scroll.hasVerticalScroller = text.frame.height > 260
        scroll.drawsBackground = false
        alert.accessoryView = scroll
        alert.runModal()
    }
}

private extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
