import AppKit
import UniformTypeIdentifiers

/// Superkeys' settings as a JSON file you can keep, edit by hand, or carry to
/// another Mac.
///
///     {
///       "version": 1,
///       "showChordsWhileHeld": true,
///       "apps": [ { "key": "B", "keyCode": 11, "bundleID": "app.zen-browser.zen", "name": "Zen" } ]
///     }
///
/// `keyCode` pins the exact physical key. To change a key by hand, edit `key`
/// and delete `keyCode`.
struct SettingsFile: Codable {
    static let version = 1

    struct App: Codable {
        var key: String
        var keyCode: Int?
        var bundleID: String
        var name: String?
    }

    var version: Int
    var showChordsWhileHeld: Bool?
    var apps: [App]

    /// What an import would apply, and what it had to leave out.
    struct Reading {
        var apps: [BoundApp]
        var showChordsWhileHeld: Bool?
        var skipped: [String]
    }

    enum ReadError: LocalizedError {
        case unreadable
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "This isn't a Superkeys settings file."
            case .newerVersion(let version):
                "This file is from a newer Superkeys (version \(version)). Update Superkeys to import it."
            }
        }
    }

    @MainActor
    static func current() -> SettingsFile {
        SettingsFile(
            version: version,
            showChordsWhileHeld: AppState.shared.showCheatSheet,
            apps: BindingsStore.shared.bindings.map {
                App(key: $0.label, keyCode: $0.keyCode, bundleID: $0.bundleID, name: $0.name)
            }
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func read(_ data: Data) throws -> Reading {
        guard let file = try? JSONDecoder().decode(SettingsFile.self, from: data) else { throw ReadError.unreadable }
        guard file.version <= version else { throw ReadError.newerVersion(file.version) }

        var apps: [BoundApp] = []
        var skipped: [String] = []
        for entry in file.apps {
            let label = entry.key.trimmingCharacters(in: .whitespaces)
            let bundleID = entry.bundleID.trimmingCharacters(in: .whitespaces)
            guard !bundleID.isEmpty else {
                skipped.append("✦ \(label): no app given.")
                continue
            }
            guard let keyCode = entry.keyCode ?? KeyCodes.keyCode(forLabel: label) else {
                skipped.append("“\(label)” isn't a key Superkeys recognises.")
                continue
            }
            if let reason = reservedReason(keyCode) {
                skipped.append("✦ \(label): \(reason)")
                continue
            }
            if let earlier = apps.first(where: { $0.keyCode == keyCode }) {
                skipped.append("✦ \(label) is listed twice; kept \(earlier.name).")
                continue
            }
            let name = entry.name ?? installedName(bundleID) ?? bundleID
            apps.append(BoundApp(keyCode: keyCode, label: label.uppercased(), bundleID: bundleID, name: name))
        }
        return Reading(apps: apps, showChordsWhileHeld: file.showChordsWhileHeld, skipped: skipped)
    }

    private static func reservedReason(_ keyCode: Int) -> String? {
        switch Int64(keyCode) {
        case let code where KeyCodes.windowKeys.contains(code):
            "that key moves windows."
        case KeyCodes.capsLock, KeyCodes.hyperF18, KeyCodes.mehF19:
            "that's the Hyper or Meh key itself."
        default:
            nil
        }
    }

    private static func installedName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }
}

/// The Import and Export buttons: panels and confirmation, attached to the
/// settings window.
@MainActor
enum SettingsTransfer {
    static func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Superkeys Settings.json"
        panel.message = "Your app shortcuts and preferences, as a file you can edit or move to another Mac."
        present(panel) { url in
            do {
                try SettingsFile.current().encoded().write(to: url, options: .atomic)
                AppState.shared.lastAction = "Exported settings"
            } catch {
                alert("Couldn't save the settings file.", error.localizedDescription)
            }
        }
    }

    static func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        present(panel) { url in
            do {
                let reading = try SettingsFile.read(Data(contentsOf: url))
                confirm(reading, from: url.lastPathComponent)
            } catch {
                alert("Couldn't import “\(url.lastPathComponent)”.", error.localizedDescription)
            }
        }
    }

    private static func confirm(_ reading: SettingsFile.Reading, from file: String) {
        let current = BindingsStore.shared.bindings.count
        let incoming = reading.apps.count
        let confirmation = NSAlert()
        confirmation.messageText = "Replace your \(plural(current, "app shortcut")) with \(plural(incoming, "shortcut")) from “\(file)”?"
        var details = ["Your current shortcuts will be removed."]
        if !reading.skipped.isEmpty {
            details.append("Skipped:\n" + reading.skipped.map { "• " + $0 }.joined(separator: "\n"))
        }
        confirmation.informativeText = details.joined(separator: "\n\n")
        confirmation.addButton(withTitle: "Replace")
        confirmation.addButton(withTitle: "Cancel")
        run(confirmation) { response in
            guard response == .alertFirstButtonReturn else { return }
            BindingsStore.shared.replaceAll(with: reading.apps)
            if let show = reading.showChordsWhileHeld { AppState.shared.showCheatSheet = show }
            AppState.shared.lastAction = "Imported \(plural(incoming, "shortcut"))"
        }
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private static func present(_ panel: NSSavePanel, then action: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            // Let the panel finish closing before any follow-up sheet appears.
            DispatchQueue.main.async { action(url) }
        }
        if let window = SettingsWindowController.shared.window, window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        run(alert) { _ in }
    }

    private static func run(_ alert: NSAlert, then action: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = SettingsWindowController.shared.window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: action)
        } else {
            action(alert.runModal())
        }
    }
}
