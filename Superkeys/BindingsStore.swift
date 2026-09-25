import AppKit

/// ✦ plus one key, or ✦ plus a key then a second key: a group, such as
/// ✦ O then P. The first key of a group can still have its own binding,
/// which runs when ✦ is released without a second key.
struct BoundApp: Codable, Equatable, Identifiable {
    var keyCode: Int
    var label: String
    var bundleID: String
    var name: String
    var keyCode2: Int?
    var label2: String?
    var id: String { KeySequence.id(keyCode, keyCode2) }
}

enum KeySequence {
    static func id(_ first: Int, _ second: Int?) -> String {
        second.map { "\(first)-\($0)" } ?? String(first)
    }

    /// "O" or "O then P", for messages.
    static func text(_ label: String, _ label2: String?) -> String {
        label2.map { "\(label) then \($0)" } ?? label
    }
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
    /// The second key of a group, as for apps.
    var keyCode2: Int?
    var label2: String?
    var id: String { KeySequence.id(keyCode, keyCode2) }

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

    func app(forKeyCode keyCode: Int, then second: Int? = nil) -> BoundApp? {
        bindings.first { $0.keyCode == keyCode && $0.keyCode2 == second }
    }

    /// Everything bound to a second key after this one, for the group panel.
    func group(_ first: Int) -> (apps: [BoundApp], keystrokes: [Keystroke]) {
        (bindings.filter { $0.keyCode == first && $0.keyCode2 != nil },
         keystrokes.filter { $0.keyCode == first && $0.keyCode2 != nil })
    }

    /// Returns an error message, or nil on success.
    func add(keyCode: Int, label: String, bundleID: String, name: String,
             then keyCode2: Int? = nil, label2: String? = nil) -> String? {
        if let error = validate(keyCode: keyCode, then: keyCode2, replacing: nil) { return error }
        bindings.append(BoundApp(keyCode: keyCode, label: label, bundleID: bundleID, name: name,
                                 keyCode2: keyCode2, label2: label2))
        commit()
        return nil
    }

    func setKey(of app: BoundApp, keyCode: Int, label: String,
                then keyCode2: Int? = nil, label2: String? = nil) -> String? {
        if let error = validate(keyCode: keyCode, then: keyCode2, replacing: app.id) { return error }
        guard let index = bindings.firstIndex(where: { $0.id == app.id }) else { return nil }
        bindings[index].keyCode2 = keyCode2
        bindings[index].label2 = label2
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
        if let error = validate(keyCode: keystroke.keyCode, then: keystroke.keyCode2, replacing: nil) { return error }
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
    /// Keys ✦ can never use, whatever follows them.
    func reservedReason(_ keyCode: Int) -> String? {
        switch Int64(keyCode) {
        case let code where KeyCodes.windowKeys.contains(code):
            return "\(Glyph.hyper) with the arrows and Return moves windows."
        case KeyCodes.capsLock, KeyCodes.hyperF18:
            return "That's the Hyper Key itself."
        case KeyCodes.mehF19:
            return "That's the Meh Key."
        default:
            return nil
        }
    }

    func validate(keyCode: Int, then second: Int? = nil, replacing id: String?) -> String? {
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
        if let second, second == Int(KeyCodes.escape) {
            return "Escape cancels a group, so it can't be the second key."
        }
        if let second, second == keyCode {
            return "The second key has to be different from the first."
        }
        if let existing = bindings.first(where: { $0.keyCode == keyCode && $0.keyCode2 == second && $0.id != id }) {
            return "\(Glyph.hyper) \(KeySequence.text(existing.label, existing.label2)) already opens \(existing.name)."
        }
        if let existing = keystrokes.first(where: { $0.keyCode == keyCode && $0.keyCode2 == second && $0.id != id }) {
            return "\(Glyph.hyper) \(KeySequence.text(existing.label, existing.label2)) already sends \(existing.sendKeys.joined(separator: " "))."
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
        HyperEventTap.shared.setBindings(
            apps: Set(bindings.map { HyperEventTap.Chord($0.keyCode, $0.keyCode2) }),
            keystrokes: Dictionary(keystrokes.map {
                (HyperEventTap.Chord($0.keyCode, $0.keyCode2), (CGKeyCode($0.sendKeyCode), $0.sendModifiers.cgFlags))
            }, uniquingKeysWith: { first, _ in first }))
    }
}
