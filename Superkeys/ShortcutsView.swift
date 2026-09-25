import AppKit
import SwiftUI

// MARK: - Installed applications

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL
    var id: String { bundleID }
}

@MainActor
final class AppCatalog: ObservableObject {
    static let shared = AppCatalog()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loaded = false
    private var loading = false
    private var icons: [String: NSImage] = [:]
    /// Lookups that found nothing; without this every redraw repeats them.
    private var missing: Set<String> = []

    /// Scans off the main thread. Called when the Shortcuts tab appears so the
    /// list is ready by the time the sheet opens.
    func loadIfNeeded() {
        guard !loaded, !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let found = AppCatalog.scan()
            await MainActor.run {
                let catalog = AppCatalog.shared
                catalog.apps = found
                catalog.loaded = true
                catalog.loading = false
            }
        }
    }

    func icon(for bundleID: String, at url: URL? = nil) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        if url == nil && missing.contains(bundleID) { return nil }
        guard let path = url?.path
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path else {
            missing.insert(bundleID)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        // Lets AppKit pick a small representation instead of scaling 1024px art.
        image.size = NSSize(width: 32, height: 32)
        icons[bundleID] = image
        return image
    }

    func isInstalled(_ bundleID: String) -> Bool {
        icon(for: bundleID) != nil
    }

    /// Called when Settings closes: forget the installed-apps list and every
    /// icon except those of apps with a key (the chord panel shows those).
    func trim() {
        apps = []
        loaded = false
        missing.removeAll()
        let bound = Set(BindingsStore.shared.bindings.map(\.bundleID))
        icons = icons.filter { bound.contains($0.key) }
    }

    /// Apps can be installed or removed while Superkeys runs.
    func forgetMissing() {
        missing.removeAll()
    }

    nonisolated private static func scan() -> [InstalledApp] {
        let directories = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        // Finder sits among a hundred-odd system agents in CoreServices, so it
        // is loaded directly rather than scanning that folder.
        let finder = app(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        var byID: [String: InstalledApp] = [:]
        for app in directories.flatMap(applications(in:)) + [finder].compactMap({ $0 })
        where byID[app.bundleID] == nil {
            byID[app.bundleID] = app
        }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func applications(in directory: String) -> [InstalledApp] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return entries.filter { $0.hasSuffix(".app") }.compactMap { entry in
            app(at: URL(fileURLWithPath: directory).appendingPathComponent(entry))
        }
    }

    /// Reads the app's Info.plist directly rather than through Bundle, which
    /// caches every bundle it opens for the life of the process (about a
    /// hundred apps' worth of dictionaries). The name is the one Finder shows.
    nonisolated private static func app(at url: URL) -> InstalledApp? {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let bundleID = info["CFBundleIdentifier"] as? String else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return InstalledApp(bundleID: bundleID, name: name, url: url)
    }
}

private struct AppIcon: View {
    let bundleID: String
    var url: URL?
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let icon = AppCatalog.shared.icon(for: bundleID, at: url) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Key recorder

/// Captures one key press while `isRecording` is on. Escape stops recording.
private struct KeyRecorder: View {
    @Binding var keyCode: Int?
    @Binding var label: String
    @Binding var isRecording: Bool
    let validate: (Int) -> String?

    @State private var monitor: Any?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { isRecording.toggle() } label: {
                Group {
                    if isRecording {
                        Text("Press a key…")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else if keyCode != nil {
                        KeyCombo(keys: [Glyph.hyper, label])
                    } else {
                        Text("Click to record")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 108, minHeight: 24)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording { install() } else { remove() }
        }
        .onAppear { if isRecording { install() } }
        .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        error = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(KeyCodes.escape) {
                isRecording = false
                return nil
            }
            let code = Int(event.keyCode)
            let name = KeyCodes.label(forKeyCode: code, characters: event.charactersIgnoringModifiers)
            guard !name.isEmpty else { return nil }
            if let failure = validate(code) {
                error = failure
                return nil
            }
            keyCode = code
            label = name
            error = nil
            isRecording = false
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Shortcuts tab

struct ShortcutsTab: View {
    @ObservedObject private var store = BindingsStore.shared
    @State private var adding = false
    @State private var addingKeystroke = false
    @State private var rekeying: BoundApp?

    var body: some View {
        Form {
            Section {
                if store.bindings.isEmpty {
                    emptyState
                } else {
                    ForEach(store.bindings) { app in
                        ShortcutRow(app: app) { rekeying = app }
                    }
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Button {
                        adding = true
                    } label: {
                        Label("Add App", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Hold \(Glyph.hyper) Caps Lock and press the key. The app opens, or comes forward if it's already running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if store.keystrokes.isEmpty {
                    HStack(spacing: 10) {
                        KeyCombo(keys: [Glyph.hyper, "C"])
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                        KeyCombo(keys: ["⌃", "C"])
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Use \(Glyph.hyper) as Control in the terminal")
                            Text("\(Glyph.hyper) C stops a command, \(Glyph.hyper) D ends input, \(Glyph.hyper) R searches history.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add All Three") {
                            for item in Keystroke.terminalSet { _ = store.add(item.stroke) }
                        }
                    }
                } else {
                    ForEach(store.keystrokes) { stroke in
                        KeystrokeRow(stroke: stroke)
                    }
                }
            } header: {
                HStack {
                    Text("Keystrokes")
                    Spacer()
                    Button {
                        addingKeystroke = true
                    } label: {
                        Label("Add Keystroke", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Sent to the app in front. Holding the key repeats it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            AppCatalog.shared.forgetMissing()
            AppCatalog.shared.loadIfNeeded()
        }
        .sheet(isPresented: $adding) {
            NewShortcutSheet()
        }
        .sheet(isPresented: $addingKeystroke) {
            NewKeystrokeSheet()
        }
        .sheet(item: $rekeying) { app in
            RebindSheet(app: app)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            KeyCombo(keys: [Glyph.hyper, "B"])
                .opacity(0.6)
            Text("No apps yet")
                .foregroundStyle(.secondary)
            Text("Give an app a key and open it from anywhere.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Add App…") { adding = true }
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct ShortcutRow: View {
    let app: BoundApp
    let rebind: () -> Void

    @State private var hovering = false

    var body: some View {
        let installed = AppCatalog.shared.isInstalled(app.bundleID)
        HStack(spacing: 10) {
            AppIcon(bundleID: app.bundleID)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .foregroundStyle(installed ? .primary : .secondary)
                if !installed {
                    Text("Not installed. Remove it, or reinstall the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: rebind) { KeyCombo(keys: [Glyph.hyper, app.label]) }
                .buttonStyle(.plain)
                .help("Change key")
            Button {
                BindingsStore.shared.remove(app)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove")
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // The hover-only button is invisible to keyboard and VoiceOver users.
        .contextMenu {
            Button("Change Key…", action: rebind)
            Button("Remove") { BindingsStore.shared.remove(app) }
        }
    }
}

// MARK: - Sheets

private struct NewShortcutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = AppCatalog.shared
    @ObservedObject private var store = BindingsStore.shared

    @State private var search = ""
    @State private var selected: InstalledApp?
    @State private var keyCode: Int?
    @State private var label = ""
    @State private var recording = false

    /// Names that start with the query rank first, closest match first, so
    /// "fin" puts Finder above Find My. Other matches follow alphabetically.
    private var results: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return catalog.apps }
        let matches = catalog.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let prefixed = matches.filter { $0.name.lowercased().hasPrefix(query.lowercased()) }
            .sorted { ($0.name.count, $0.name) < ($1.name.count, $1.name) }
        let rest = matches.filter { !$0.name.lowercased().hasPrefix(query.lowercased()) }
        return prefixed + rest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Shortcut").font(.headline)
                Text("Choose an app, then press the key alone. \(Glyph.hyper) is added for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search applications", text: $search)
                    .textFieldStyle(.plain)
                    .onSubmit(confirm)
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            if results.isEmpty {
                VStack(spacing: 4) {
                    Text(catalog.loaded ? "No applications match" : "Looking for applications…")
                        .foregroundStyle(.secondary)
                    if catalog.loaded {
                        Text("Try a different name.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { app in
                                AppRow(app: app,
                                       selected: selected?.bundleID == app.bundleID,
                                       existingKey: store.bindings.first { $0.bundleID == app.bundleID }?.label) {
                                    choose(app)
                                }
                                .id(app.bundleID)
                            }
                        }
                    }
                    .onChange(of: selected) { _, app in
                        if let app { proxy.scrollTo(app.bundleID) }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            HStack(alignment: .top) {
                KeyRecorder(keyCode: $keyCode, label: $label, isRecording: $recording) {
                    store.validate(keyCode: $0, replacing: nil)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Add", action: add)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selected == nil || keyCode == nil)
                }
            }
            .padding(16)
        }
        .frame(width: 420, height: 470)
        .onAppear { catalog.loadIfNeeded() }
        // Keep the top match highlighted so Return picks it.
        .onChange(of: search) { _, _ in selected = results.first }
    }

    /// Arrow keys only move the highlight; Return or a click commits it.
    private func moveSelection(_ step: Int) {
        guard !results.isEmpty else { return }
        let current = selected.flatMap { app in results.firstIndex { $0.bundleID == app.bundleID } }
        let next = current.map { min(max($0 + step, 0), results.count - 1) } ?? 0
        selected = results[next]
    }

    /// Committing an app is the cue to press its key, so recording starts.
    private func choose(_ app: InstalledApp) {
        selected = app
        if keyCode == nil { recording = true }
    }

    private func confirm() {
        if selected != nil && keyCode != nil {
            add()
        } else if let app = selected ?? results.first {
            choose(app)
        }
    }

    private func add() {
        guard let selected, let keyCode else { return }
        if store.add(keyCode: keyCode, label: label, bundleID: selected.bundleID, name: selected.name) == nil {
            dismiss()
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let selected: Bool
    let existingKey: String?
    let select: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(bundleID: app.bundleID, url: app.url, size: 20)
            Text(app.name)
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer()
            if let existingKey {
                KeyCombo(keys: [Glyph.hyper, existingKey])
                    .opacity(selected ? 0.9 : 0.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}

private struct RebindSheet: View {
    let app: BoundApp
    @Environment(\.dismiss) private var dismiss

    @State private var keyCode: Int?
    @State private var label = ""
    // The sheet exists to take a new key, so it listens straight away.
    @State private var recording = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppIcon(bundleID: app.bundleID, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.headline)
                    Text("Press the new key alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            KeyRecorder(keyCode: $keyCode, label: $label, isRecording: $recording) {
                BindingsStore.shared.validate(keyCode: $0, replacing: app.id)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let keyCode else { return }
                    if BindingsStore.shared.setKey(of: app, keyCode: keyCode, label: label) == nil {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keyCode == nil || keyCode == app.keyCode)
            }
        }
        .padding(18)
        .frame(width: 320)
        .onAppear {
            keyCode = app.keyCode
            label = app.label
        }
    }
}

// MARK: - Keystrokes

private struct KeystrokeRow: View {
    let stroke: Keystroke
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            KeyCombo(keys: [Glyph.hyper, stroke.label])
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
            KeyCombo(keys: stroke.sendKeys)
            Spacer()
            Button {
                BindingsStore.shared.remove(stroke)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove")
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hyper \(stroke.label) sends \(stroke.sendText)")
        .contextMenu {
            Button("Remove") { BindingsStore.shared.remove(stroke) }
        }
    }
}

private struct NewKeystrokeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var keyCode: Int?
    @State private var label = ""
    @State private var recordingKey = true
    @State private var send: (keyCode: Int, modifiers: Keystroke.Modifiers, label: String)?
    @State private var recordingSend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Keystroke").font(.headline)
                Text("\(Glyph.hyper) plus a key sends another key combination to the app in front.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Key").foregroundStyle(.secondary)
                    KeyRecorder(keyCode: $keyCode, label: $label, isRecording: $recordingKey) {
                        BindingsStore.shared.validate(keyCode: $0, replacing: nil)
                    }
                }
                GridRow {
                    Text("Sends").foregroundStyle(.secondary)
                    ComboRecorder(combo: $send, isRecording: $recordingSend)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(keyCode == nil || send == nil)
            }
        }
        .padding(18)
        .frame(width: 380)
        // Once the key is in, listen for what it sends.
        .onChange(of: keyCode) { _, code in
            if code != nil, send == nil { recordingSend = true }
        }
        .onChange(of: recordingSend) { _, on in if on { recordingKey = false } }
        .onChange(of: recordingKey) { _, on in if on { recordingSend = false } }
    }

    private func add() {
        guard let keyCode, let send else { return }
        let stroke = Keystroke(keyCode: keyCode, label: label, sendKeyCode: send.keyCode,
                               sendModifiers: send.modifiers, sendLabel: send.label)
        if BindingsStore.shared.add(stroke) == nil { dismiss() }
    }
}

/// Records a whole key combination, modifiers included, e.g. ⌃ C.
private struct ComboRecorder: View {
    @Binding var combo: (keyCode: Int, modifiers: Keystroke.Modifiers, label: String)?
    @Binding var isRecording: Bool
    @State private var monitor: Any?

    var body: some View {
        Button { isRecording.toggle() } label: {
            Group {
                if isRecording {
                    Text("Press the combination…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if let combo {
                    KeyCombo(keys: Keystroke.Modifiers.ordered.filter { combo.modifiers.contains($0.0) }.map(\.symbol)
                                 + [combo.label])
                } else {
                    Text("Click to record")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 108, minHeight: 24)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, recording in
            if recording { install() } else { remove() }
        }
        .onAppear { if isRecording { install() } }
        .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape alone cancels; with a modifier it's a combination to send.
            let modifiers = Keystroke.Modifiers(event.modifierFlags)
            if event.keyCode == UInt16(KeyCodes.escape), modifiers.isEmpty {
                isRecording = false
                return nil
            }
            let code = Int(event.keyCode)
            var name = KeyCodes.label(forKeyCode: code, characters: event.charactersIgnoringModifiers)
            if name.isEmpty { name = KeyCodes.label(forKeyCode: code, characters: nil) }
            guard !name.isEmpty else { return nil }
            combo = (code, modifiers, name)
            isRecording = false
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
