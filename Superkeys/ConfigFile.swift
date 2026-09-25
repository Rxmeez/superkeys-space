import AppKit
import Combine

/// Superkeys' settings as a plain text file, `~/.config/superkeys/config.toml`,
/// kept in step with the app both ways: changes made in Settings are written
/// to it, and saving it in an editor applies it straight away. Keep it in your
/// dotfiles to carry your setup to another Mac.
///
///     show_chords_while_held = true
///     desktop_numbering = "global"
///
///     [apps]
///     B = "app.zen-browser.zen"  # Zen
///
/// Only a small part of TOML is needed and understood: comments, `key = value`
/// with strings, booleans and whole numbers, and the one `[apps]` table.
struct ConfigFile {
    var showChordsWhileHeld = true
    var desktopNumbering = SpaceManager.Numbering.global
    var apps: [BoundApp] = []

    /// Something in the file Superkeys couldn't use, by line.
    struct Problem: Equatable, Identifiable {
        let line: Int
        let message: String
        var id: String { "\(line):\(message)" }
    }

    struct Reading {
        var config: ConfigFile
        var problems: [Problem]
        /// The file couldn't be read as TOML at all, or not everywhere: then
        /// nothing in it is applied, so a typo never wipes your settings.
        var syntaxError: Bool
    }

    // MARK: Writing

    func text() -> String {
        var out = """
        # Superkeys settings
        #
        # Superkeys applies this file as soon as it's saved, and rewrites it when
        # you change something in Settings. Keep it in your dotfiles to carry your
        # setup to another Mac.

        # Hold ✦ or ☾ for a moment, without pressing anything else, to see a panel
        # of everything that key does.
        show_chords_while_held = \(showChordsWhileHeld)

        # ☾ 1–9 always mean the desktops of the display under the pointer. This
        # only tells Superkeys how macOS numbers its own "Switch to Desktop"
        # shortcuts: "global" (across all displays, as macOS does) or
        # "per-display". Change it only if ☾ goes to the wrong display.
        desktop_numbering = "\(desktopNumbering == .global ? "global" : "per-display")"

        # ✦ plus a key opens an app, or brings it forward. Write keys as you'd type
        # them ("B", "5", "F5", ";") and apps by bundle ID. To find an app's ID:
        #   osascript -e 'id of app "Safari"'
        [apps]

        """
        let entries = apps.map { (key: Self.tomlKey(for: $0), app: $0) }
        let width = entries.map(\.key.count).max() ?? 0
        for entry in entries {
            let padding = String(repeating: " ", count: width - entry.key.count)
            out += "\(entry.key)\(padding) = \(Self.quoted(entry.app.bundleID))  # \(entry.app.name)\n"
        }
        return out
    }

    /// The key as written in the file: its label when that reads back as the
    /// same physical key, otherwise the raw key code, e.g. "code:50".
    private static func tomlKey(for app: BoundApp) -> String {
        let label = KeyCodes.keyCode(forLabel: app.label) == app.keyCode ? app.label : "code:\(app.keyCode)"
        let bare = label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        return bare ? label : quoted(label)
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: Reading

    static func read(_ text: String) -> Reading {
        var config = ConfigFile()
        var problems: [Problem] = []
        var syntaxError = false
        var section = ""
        var seenKeys = Set<Int>()

        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let number = index + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                guard let close = line.firstIndex(of: "]") else {
                    problems.append(Problem(line: number, message: "A section name needs a closing ]."))
                    syntaxError = true
                    continue
                }
                section = String(line[line.index(after: line.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
                if section != "apps" {
                    problems.append(Problem(line: number, message: "Superkeys doesn't know a [\(section)] section; it's ignored."))
                }
                continue
            }

            guard let (key, value) = splitAssignment(line) else {
                problems.append(Problem(line: number, message: "Expected key = value."))
                syntaxError = true
                continue
            }

            switch (section, key) {
            case ("", "show_chords_while_held"):
                guard case .bool(let on) = value else {
                    problems.append(Problem(line: number, message: "show_chords_while_held is true or false."))
                    continue
                }
                config.showChordsWhileHeld = on
            case ("", "desktop_numbering"):
                switch value {
                case .string("global"): config.desktopNumbering = .global
                case .string("per-display"): config.desktopNumbering = .perDisplay
                default: problems.append(Problem(line: number, message: "desktop_numbering is \"global\" or \"per-display\"."))
                }
            case ("apps", _):
                guard case .string(let bundleID) = value, !bundleID.isEmpty else {
                    problems.append(Problem(line: number, message: "✦ \(key): the app goes in quotes, as its bundle ID."))
                    continue
                }
                guard let keyCode = keyCode(for: key) else {
                    problems.append(Problem(line: number, message: "“\(key)” isn't a key Superkeys recognises."))
                    continue
                }
                if let reason = reservedReason(keyCode) {
                    problems.append(Problem(line: number, message: "✦ \(key): \(reason)"))
                    continue
                }
                guard seenKeys.insert(keyCode).inserted else {
                    problems.append(Problem(line: number, message: "✦ \(key) is listed twice; the first one is kept."))
                    continue
                }
                let label = key.hasPrefix("code:") ? KeyCodes.label(forKeyCode: keyCode, characters: nil) : key.uppercased()
                config.apps.append(BoundApp(keyCode: keyCode, label: label, bundleID: bundleID,
                                            name: installedName(bundleID) ?? bundleID))
            default:
                problems.append(Problem(line: number, message: "Superkeys doesn't know “\(key)”; it's ignored."))
            }
        }
        return Reading(config: config, problems: problems, syntaxError: syntaxError)
    }

    private enum Value: Equatable {
        case string(String), bool(Bool), int(Int)
    }

    /// `key = value  # comment`, with the key bare or quoted.
    private static func splitAssignment(_ line: String) -> (String, Value)? {
        var rest = Substring(line)
        let key: String
        if rest.hasPrefix("\"") {
            guard let (string, after) = quotedString(rest) else { return nil }
            key = string
            rest = after
        } else {
            guard let equals = rest.firstIndex(of: "=") else { return nil }
            key = rest[..<equals].trimmingCharacters(in: .whitespaces)
            rest = rest[equals...]
            guard !key.isEmpty, !key.contains(" ") else { return nil }
        }
        rest = rest.drop(while: { $0 == " " || $0 == "\t" })
        guard rest.hasPrefix("=") else { return nil }
        rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" })

        let value: Value
        if rest.hasPrefix("\"") {
            guard let (string, after) = quotedString(rest) else { return nil }
            value = .string(string)
            rest = after
        } else {
            let token = rest.prefix(while: { $0 != " " && $0 != "\t" && $0 != "#" })
            rest = rest.dropFirst(token.count)
            switch token {
            case "true": value = .bool(true)
            case "false": value = .bool(false)
            default:
                guard let n = Int(token) else { return nil }
                value = .int(n)
            }
        }
        // Only whitespace or a comment may follow.
        let tail = rest.trimmingCharacters(in: .whitespaces)
        guard tail.isEmpty || tail.hasPrefix("#") else { return nil }
        return (key, value)
    }

    /// A "basic string" at the start of `text`, and whatever follows it.
    private static func quotedString(_ text: Substring) -> (String, Substring)? {
        var result = ""
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let c = text[index]
            if c == "\"" { return (result, text[text.index(after: index)...]) }
            if c == "\\" {
                index = text.index(after: index)
                guard index < text.endIndex else { return nil }
                switch text[index] {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(text[index])
                }
            } else {
                result.append(c)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func keyCode(for key: String) -> Int? {
        if key.hasPrefix("code:") { return Int(key.dropFirst(5)) }
        return KeyCodes.keyCode(forLabel: key)
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
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return name
    }
}

/// Keeps config.toml and the app's settings the same, whichever changed.
@MainActor
final class ConfigSync: ObservableObject {
    static let shared = ConfigSync()

    /// `$XDG_CONFIG_HOME/superkeys/config.toml`, normally under ~/.config.
    /// Development builds keep their own, so testing never touches yours.
    let url: URL = {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        #if DEBUG
        let folder = "superkeys-dev"
        #else
        let folder = "superkeys"
        #endif
        return base.appendingPathComponent(folder).appendingPathComponent("config.toml")
    }()

    /// The path as people would type it, with ~ for the home folder.
    var displayPath: String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    @Published private(set) var problems: [ConfigFile.Problem] = []
    /// The last read didn't apply because the file has a syntax error.
    @Published private(set) var notApplied = false

    private var lastText: String?
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pendingLoad: DispatchWorkItem?
    private var observers: Set<AnyCancellable> = []
    private var applying = false
    private var pendingWrite: DispatchWorkItem?

    private init() {}

    /// At launch: an existing file wins over what the app had; otherwise the
    /// app's settings become the file.
    func start() {
        if FileManager.default.fileExists(atPath: url.path) {
            load()
        } else {
            write()
        }
        watch()
        BindingsStore.shared.$bindings.dropFirst().sink { [weak self] _ in self?.scheduleWrite() }.store(in: &observers)
        AppState.shared.$showCheatSheet.dropFirst().sink { [weak self] _ in self?.scheduleWrite() }.store(in: &observers)
    }

    /// Superkeys' settings as they are now.
    static func current() -> ConfigFile {
        ConfigFile(showChordsWhileHeld: AppState.shared.showCheatSheet,
                   desktopNumbering: SpaceManager.numbering,
                   apps: BindingsStore.shared.bindings)
    }

    func open() {
        if !FileManager.default.fileExists(atPath: url.path) { write() }
        // .toml often has no app of its own; fall back to TextEdit.
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func revealInFinder() {
        if !FileManager.default.fileExists(atPath: url.path) { write() }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: File → app

    private func load() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        guard text != lastText else { return }
        lastText = text
        let reading = ConfigFile.read(text)
        problems = reading.problems
        notApplied = reading.syntaxError
        guard !reading.syntaxError else { return }
        apply(reading.config)
    }

    private func apply(_ config: ConfigFile) {
        applying = true
        defer { applying = false }
        if AppState.shared.showCheatSheet != config.showChordsWhileHeld {
            AppState.shared.showCheatSheet = config.showChordsWhileHeld
        }
        if SpaceManager.numbering != config.desktopNumbering {
            UserDefaults.standard.set(config.desktopNumbering.rawValue, forKey: "desktopNumbering")
        }
        let current = BindingsStore.shared.bindings
        let same = current.count == config.apps.count && zip(current, config.apps).allSatisfy {
            $0.keyCode == $1.keyCode && $0.bundleID == $1.bundleID
        }
        if !same { BindingsStore.shared.replaceAll(with: config.apps) }
        AppState.shared.lastAction = "Applied config.toml"
    }

    /// Editors save either by writing into the file or by replacing it with
    /// a new one, so watch both the file and its folder; the file watch is
    /// re-attached after every change, since a replaced file is a new file.
    private func watch() {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folderWatcher = source(for: folder.path, events: [.write, .rename, .delete])
        watchFile()
    }

    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = source(for: url.path, events: [.write, .extend, .delete, .rename])
    }

    private func source(for path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func changed() {
        pendingLoad?.cancel()
        // Let the editor finish saving, then read once.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.load()
                self?.watchFile()
            }
        }
        pendingLoad = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: App → file

    private func scheduleWrite() {
        // While the file has a syntax error it's mid-edit: never overwrite it.
        guard !applying, !notApplied else { return }
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.write() }
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func write() {
        let text = Self.current().text()
        guard text != lastText else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastText = text
            watchFile()
            problems = []
            notApplied = false
        } catch {
            AppState.shared.lastAction = "Couldn't save config.toml"
        }
    }
}
