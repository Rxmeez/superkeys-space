import AppKit

struct BoundApp: Codable, Equatable, Identifiable {
    var keyCode: Int
    var label: String
    var bundleID: String
    var name: String
    var id: String { String(keyCode) }
}

/// ✦ plus a key sends another key combination to the app in front, e.g.
/// ✦ C sends ⌃ C.
struct Keystroke: Codable, Equatable, Identifiable {
    var keyCode: Int
    var label: String
    /// What's sent.
    var sendKeyCode: Int
    var sendModifiers: Modifiers
    var sendLabel: String
    var id: String { String(keyCode) }

    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)

        /// In macOS's order: ⌃ ⌥ ⇧ ⌘.
        static let ordered: [(Modifiers, symbol: String, name: String)] = [
            (.control, "⌃", "ctrl"), (.option, "⌥", "opt"), (.shift, "⇧", "shift"), (.command, "⌘", "cmd"),
        ]

        var cgFlags: CGEventFlags {
            var flags: CGEventFlags = []
            if contains(.control) { flags.insert(.maskControl) }
            if contains(.option) { flags.insert(.maskAlternate) }
            if contains(.shift) { flags.insert(.maskShift) }
            if contains(.command) { flags.insert(.maskCommand) }
            return flags
        }

        init(rawValue: Int) { self.rawValue = rawValue }

        init(_ flags: NSEvent.ModifierFlags) {
            var m: Modifiers = []
            if flags.contains(.control) { m.insert(.control) }
            if flags.contains(.option) { m.insert(.option) }
            if flags.contains(.shift) { m.insert(.shift) }
            if flags.contains(.command) { m.insert(.command) }
            self = m
        }
    }

    /// ✦ as Control for the terminal: stop a command, end input, search
    /// history. Offered in the tour and in an empty Keystrokes list.
    static let terminalSet: [(stroke: Keystroke, purpose: String)] = [
        (Keystroke(keyCode: 8, label: "C", sendKeyCode: 8, sendModifiers: .control, sendLabel: "C"), "Stop a running command"),
        (Keystroke(keyCode: 2, label: "D", sendKeyCode: 2, sendModifiers: .control, sendLabel: "D"), "End input, or close the shell"),
        (Keystroke(keyCode: 15, label: "R", sendKeyCode: 15, sendModifiers: .control, sendLabel: "R"), "Search your command history"),
    ]

    /// The combination as keycaps, e.g. ["⌃", "C"].
    var sendKeys: [String] {
        Modifiers.ordered.filter { sendModifiers.contains($0.0) }.map(\.symbol) + [sendLabel]
    }

    /// As written in the config file, e.g. "ctrl+c".
    var sendText: String {
        let key = sendLabel.count == 1 ? sendLabel.lowercased() : sendLabel
        return (Modifiers.ordered.filter { sendModifiers.contains($0.0) }.map(\.name) + [key]).joined(separator: "+")
    }

    /// Reads a combination as written in the config file: "ctrl+c", "cmd+shift+t".
    static func parse(_ text: String) -> (keyCode: Int, modifiers: Modifiers, label: String)? {
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        // "ctrl++" means the + key.
        if text.hasSuffix("++") { parts.removeLast(2); parts.append("+") }
        guard let keyText = parts.popLast(), !keyText.isEmpty else { return nil }
        var modifiers: Modifiers = []
        for part in parts {
            switch part.lowercased() {
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "cmd", "command": modifiers.insert(.command)
            default: return nil
            }
        }
        guard let code = KeyCodes.keyCode(forLabel: keyText) else { return nil }
        let label = KeyCodes.label(forKeyCode: code, characters: keyText.count == 1 ? keyText : nil)
        return (code, modifiers, label.isEmpty ? keyText.uppercased() : label)
    }
}

@MainActor
final class BindingsStore: ObservableObject {
    static let shared = BindingsStore()

    private static let defaultsKey = "bindings.v2"

    @Published private(set) var bindings: [BoundApp]
    private static let keystrokesKey = "keystrokes.v1"
    @Published private(set) var keystrokes: [Keystroke]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([BoundApp].self, from: data) {
            bindings = decoded
        } else {
            bindings = []
        }
        if let data = UserDefaults.standard.data(forKey: Self.keystrokesKey),
           let decoded = try? JSONDecoder().decode([Keystroke].self, from: data) {
            keystrokes = decoded
        } else {
            keystrokes = []
        }
        syncTap()
    }

    func app(forKeyCode keyCode: Int) -> BoundApp? {
        bindings.first { $0.keyCode == keyCode }
    }

    /// Returns an error message, or nil on success.
    func add(keyCode: Int, label: String, bundleID: String, name: String) -> String? {
        if let error = validate(keyCode: keyCode, replacing: nil) { return error }
        bindings.append(BoundApp(keyCode: keyCode, label: label, bundleID: bundleID, name: name))
        commit()
        return nil
    }

    func setKey(of app: BoundApp, keyCode: Int, label: String) -> String? {
        if let error = validate(keyCode: keyCode, replacing: app.id) { return error }
        guard let index = bindings.firstIndex(where: { $0.id == app.id }) else { return nil }
        bindings[index].keyCode = keyCode
        bindings[index].label = label
        commit()
        return nil
    }

    func remove(_ app: BoundApp) {
        bindings.removeAll { $0.id == app.id }
        commit()
    }

    /// Returns an error message, or nil on success.
    func add(_ keystroke: Keystroke) -> String? {
        if let error = validate(keyCode: keystroke.keyCode, replacing: nil) { return error }
        keystrokes.append(keystroke)
        commit()
        return nil
    }

    func remove(_ keystroke: Keystroke) {
        keystrokes.removeAll { $0.id == keystroke.id }
        commit()
    }

    func replaceAll(apps: [BoundApp], keystrokes: [Keystroke]) {
        bindings = apps
        self.keystrokes = keystrokes
        commit()
    }

    /// Returns a reason the key cannot be used, or nil when it is free.
    func validate(keyCode: Int, replacing id: String?) -> String? {
        switch Int64(keyCode) {
        case let code where KeyCodes.windowKeys.contains(code):
            return "\(Glyph.hyper) with the arrows and Return moves windows."
        case KeyCodes.capsLock, KeyCodes.hyperF18:
            return "That's the Hyper Key itself."
        case KeyCodes.mehF19:
            return "That's the Meh Key."
        default:
            break
        }
        if let existing = bindings.first(where: { $0.keyCode == keyCode && $0.id != id }) {
            return "\(Glyph.hyper) \(existing.label) already opens \(existing.name)."
        }
        if let existing = keystrokes.first(where: { $0.keyCode == keyCode && $0.id != id }) {
            return "\(Glyph.hyper) \(existing.label) already sends \(existing.sendKeys.joined(separator: " "))."
        }
        return nil
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        if let data = try? JSONEncoder().encode(keystrokes) {
            UserDefaults.standard.set(data, forKey: Self.keystrokesKey)
        }
        syncTap()
    }

    private func syncTap() {
        HyperEventTap.shared.setAppKeyCodes(Set(bindings.map { Int64($0.keyCode) }))
        HyperEventTap.shared.setKeystrokes(Dictionary(uniqueKeysWithValues: keystrokes.map {
            (Int64($0.keyCode), (CGKeyCode($0.sendKeyCode), $0.sendModifiers.cgFlags))
        }))
    }
}
