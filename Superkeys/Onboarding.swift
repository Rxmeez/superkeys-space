import AppKit
import Combine
import SwiftUI

/// A short, hands-on setup: five steps, each of which waits for you to do the
/// thing rather than describing it. Shown once to new users; "Take the Tour"
/// in Settings → General brings it back.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static let completedKey = "onboardingCompleted"
    private static var current: OnboardingWindowController?
    #if DEBUG
    static var debugStartStep = 0

    /// Opens a fresh tour at a given step, for screenshots.
    static func debugShow(step: Int) {
        current?.window?.orderOut(nil)
        current = nil
        debugStartStep = step
        show()
    }
    #endif

    private static var quitting = false
    private static let quitObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: nil
    ) { _ in quitting = true }

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    /// New users start with the tour pending; people upgrading from a
    /// version without it are already set up and skip it.
    static func noteLaunch(firstLaunch: Bool) {
        guard UserDefaults.standard.object(forKey: completedKey) == nil else { return }
        hasCompleted = !firstLaunch
    }

    static func show() {
        _ = quitObserver
        let controller = current ?? OnboardingWindowController()
        current = controller
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let tour = TourModel()

    /// ✦ ← / → step through the tour while it's the window in front, instead
    /// of snapping it; that's also how the tour teaches the chord.
    static func handleHyperArrow(_ side: WindowManager.Side) -> Bool {
        guard NSApp.isActive, let controller = current, controller.window?.isKeyWindow == true else { return false }
        side == .left ? controller.tour.back() : controller.tour.skipAhead()
        return true
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.title = "Welcome to Superkeys"
        super.init(window: window)
        window.delegate = self
        tour.finish = { [weak self] in self?.close() }
        window.contentViewController = NSHostingController(rootView: OnboardingView(tour: tour)
            .environmentObject(AppState.shared))
        window.setContentSize(NSSize(width: 680, height: 520))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func windowWillClose(_ notification: Notification) {
        // Closing early counts as done too; the tour is always one click away.
        // Quitting doesn't: macOS may offer to quit and reopen after access is
        // granted, and the tour should still be there afterwards.
        if !Self.quitting { Self.hasCompleted = true }
        DispatchQueue.main.async {
            Self.current = nil
            if SettingsWindowController.isOpen == false { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

// MARK: - Steps

private enum Step: Int, CaseIterable {
    case welcome, access, tryHyper, apps, tryMeh, keystrokes
}

/// Where the tour is, and what its main button does on each step, shared by
/// the buttons and ✦ ← / →.
@MainActor
private final class TourModel: ObservableObject {
    @Published var step: Step = {
        #if DEBUG
        return Step(rawValue: OnboardingWindowController.debugStartStep) ?? .welcome
        #else
        return .welcome
        #endif
    }()
    /// Which way the last move went, so steps slide in from the right side.
    @Published var forward = true
    let picks = AppPicks()
    let strokes = KeystrokePicks()
    var finish: () -> Void = {}
    private var picksChanged: Set<AnyCancellable> = []

    init() {
        // The main button's title counts what's ticked.
        picks.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &picksChanged)
        strokes.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &picksChanged)
    }

    /// The main button: on the apps step it adds the ticked keys first.
    func next() {
        switch step {
        case .apps: picks.add(); move(1)
        case .keystrokes: strokes.add(); finish()
        default: move(1)
        }
    }

    func back() { move(-1) }

    /// ✦ →: onward without choosing anything; adding keys and finishing are
    /// the buttons' job.
    func skipAhead() {
        if step != .keystrokes { move(1) }
    }

    func move(_ delta: Int) {
        guard let target = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(.easeInOut(duration: 0.28)) { step = target }
    }
}

private struct OnboardingView: View {
    @ObservedObject var tour: TourModel
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: Step { tour.step }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .access: AccessStep()
                case .tryHyper: TryHyperStep()
                case .apps: AppsStep(picks: tour.picks)
                case .tryMeh: MehStep()
                case .keystrokes: KeystrokesStep(picks: tour.strokes)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: tour.forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: tour.forward ? .leading : .trailing).combined(with: .opacity)))
            .id(step)

            footer
        }
        .frame(width: 680, height: 520)
        .clipped()
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [Accent.hyper.opacity(0.12), .clear], center: UnitPoint(x: 0.3, y: 0), startRadius: 0, endRadius: 360)
                RadialGradient(colors: [Accent.meh.opacity(0.12), .clear], center: UnitPoint(x: 0.75, y: 0), startRadius: 0, endRadius: 360)
            }
            .ignoresSafeArea()
        )
        // Access granted while on that step: move on by itself.
        .onChange(of: state.accessibilityTrusted) { _, trusted in
            if trusted, step == .access {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { tour.move(1) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    ForEach(Step.allCases, id: \.self) { s in
                        Capsule()
                            .fill(s == step ? Accent.hyper : Color.secondary.opacity(0.3))
                            .frame(width: s == step ? 18 : 7, height: 7)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: step)
                .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                // Only once the keys work; before that the chord does nothing.
                if state.accessibilityTrusted {
                    HStack(spacing: 6) {
                        KeyCombo(keys: [Glyph.hyper, "←", "→"])
                            .scaleEffect(0.85, anchor: .leading)
                        Text("to move through the tour")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .offset(x: -10)
                    }
                }
            }
            Spacer()
            if step != .welcome {
                Button("Back") { tour.back() }
                    .controlSize(.large)
            }
            if step == .apps, !tour.picks.chosen.isEmpty {
                Button("Skip") { tour.skipAhead() }
                    .controlSize(.large)
            }
            if step == .keystrokes, !tour.strokes.chosen.isEmpty {
                Button("Skip") { tour.finish() }
                    .controlSize(.large)
            }
            primaryButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .access: return state.accessibilityTrusted ? "Continue" : "Skip for Now"
        case .tryHyper: return "Continue"
        case .apps:
            let n = tour.picks.chosen.count
            return n == 0 ? "Skip" : "Add \(n) \(n == 1 ? "Key" : "Keys")"
        case .tryMeh: return "Continue"
        case .keystrokes:
            let n = tour.strokes.chosen.count
            return n == 0 ? "Done" : "Add \(n) & Finish"
        }
    }

    private var primaryButton: some View {
        Button(primaryTitle) { tour.next() }
            .keyboardShortcut(step == .access && !state.accessibilityTrusted ? nil : .defaultAction)
            .controlSize(.large)
    }
}

// MARK: Shared pieces

private struct StepHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
    }
}

/// A large keycap that lights in its accent colour while `lit`.
private struct BigKey: View {
    let symbol: String
    let legend: String
    let accent: Color
    let lit: Bool
    var size: CGFloat = 104

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(lit ? AnyShapeStyle(Accent.gradient(accent)) : AnyShapeStyle(accent.opacity(0.12)))
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(lit ? Color.white : accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -size * 0.08)
            Text(legend)
                .font(.system(size: size * 0.11))
                .foregroundStyle(lit ? Color.white.opacity(0.85) : .secondary)
                .padding(.leading, size * 0.13)
                .padding(.bottom, size * 0.11)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .stroke(accent.opacity(lit ? 0 : 0.35), lineWidth: 1))
        .shadow(color: accent.opacity(lit ? 0.55 : 0.15), radius: lit ? 22 : 12)
        .scaleEffect(lit ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: lit)
    }
}

/// Part of a Mac keyboard with the key to use outlined, for the two keys
/// people wouldn't guess: Caps Lock, and the right ⌘ rather than the left
/// one. The key lights up while the real one is held.
private struct KeyboardRow: View {
    struct Key: Identifiable {
        let id: Int
        var symbol = ""
        var word = ""
        var width: CGFloat = 1
        var target = false
        /// A look-alike to steer away from, shown faded with this note.
        var decoy: String?
        /// Caps Lock's little light.
        var light = false
    }

    /// Top to bottom. With one row the pointer sits under the key; with
    /// several it sits beside the key's row.
    let rows: [[Key]]
    let accent: Color
    /// Shown on the target key while it's down.
    let litSymbol: String
    let held: Bool
    let description: String

    private let unit: CGFloat = 40

    static func capsLock(held: Bool) -> KeyboardRow {
        func letters(_ text: String) -> [Key] {
            text.enumerated().map { Key(id: $0.offset + 1, symbol: String($0.element)) }
        }
        return KeyboardRow(rows: [
            [Key(id: 0, symbol: "⇥", word: "tab", width: 1.5)] + letters("QWE"),
            [Key(id: 0, word: "caps lock", width: 1.8, target: true, light: true)] + letters("ASD"),
            [Key(id: 0, symbol: "⇧", word: "shift", width: 2.35)] + letters("ZXC"),
        ], accent: Accent.hyper, litSymbol: "sparkle", held: held,
           description: "Caps Lock, between Tab and Shift at the left of the keyboard")
    }

    static func rightCommand(held: Bool) -> KeyboardRow {
        KeyboardRow(rows: [[
            Key(id: 0, word: "fn"),
            Key(id: 1, symbol: "⌃", word: "control"),
            Key(id: 2, symbol: "⌥", word: "option"),
            Key(id: 3, symbol: "⌘", word: "command", width: 1.35, decoy: "not this"),
            Key(id: 4, width: 4.4),
            Key(id: 5, symbol: "⌘", word: "command", width: 1.35, target: true),
            Key(id: 6, symbol: "⌥", word: "option"),
        ]], accent: Accent.meh, litSymbol: "moon.fill", held: held,
           description: "The right-hand Command key, beside the space bar")
    }

    var body: some View {
        Group {
            if rows.count == 1 { singleRow(rows[0]) } else { block }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    private var pointer: some View {
        Label("this one", systemImage: "arrow.up")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
            .fixedSize()
    }

    private func keys(_ row: [Key]) -> some View {
        HStack(spacing: 5) {
            ForEach(row) { key in cap(key, down: key.target && held) }
        }
    }

    /// One row, pointer and notes underneath.
    private func singleRow(_ row: [Key]) -> some View {
        VStack(spacing: 6) {
            keys(row)
            HStack(spacing: 5) {
                ForEach(row) { key in
                    Group {
                        if key.target {
                            pointer
                        } else if let decoy = key.decoy {
                            Text(decoy)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: key.width * unit, height: 14)
                }
            }
        }
    }

    /// Several rows, left-aligned like the edge of a keyboard and fading out
    /// to the right; the pointer sits beside the row with the key.
    private var block: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 5) {
                ForEach(rows.indices, id: \.self) { i in
                    Group {
                        if rows[i].contains(where: \.target) {
                            Label("this one", systemImage: "arrow.right")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accent)
                                .fixedSize()
                        } else {
                            Color.clear.frame(width: 0)
                        }
                    }
                    .frame(height: unit)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(rows.indices, id: \.self) { i in keys(rows[i]) }
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
    }

    private func cap(_ key: Key, down: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let ink: Color = down ? .white : (key.target ? .primary : .secondary)
        return ZStack {
            shape.fill(Color.primary.opacity(0.07))
            shape.fill(Accent.gradient(accent)).opacity(down ? 1 : 0)
            shape.stroke(key.target ? accent.opacity(down ? 0 : 0.6) : Color.primary.opacity(0.1), lineWidth: 1)
            if key.word.isEmpty {
                // Letter keys: one centred character.
                Text(key.symbol).font(.system(size: 13)).foregroundStyle(ink)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if key.light {
                            Circle().fill(down ? Color.white.opacity(0.9) : Color.secondary.opacity(0.35))
                                .frame(width: 4, height: 4)
                        }
                        Spacer()
                        if key.target && down {
                            Image(systemName: litSymbol).font(.system(size: 9))
                        } else {
                            Text(key.symbol).font(.system(size: 11))
                        }
                    }
                    Spacer()
                    Text(key.word).font(.system(size: 8.5))
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
        }
        .frame(width: key.width * unit, height: unit)
        .opacity(key.decoy != nil ? 0.45 : 1)
        .shadow(color: key.target ? accent.opacity(down ? 0.6 : 0.2) : .clear, radius: down ? 14 : 6)
        .offset(y: down ? 1.5 : 0)
        .scaleEffect(down ? 0.96 : 1)
    }
}

/// Shown on the try-it steps when Accessibility was skipped: without it
/// Superkeys can't see the keys, so holding one would do nothing.
private struct NeedsAccess: View {
    var body: some View {
        VStack(spacing: 10) {
            Button {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            } label: {
                Label("Open Accessibility Settings", systemImage: "arrow.up.forward.app")
            }
            .controlSize(.large)
            Text("Switch on Superkeys in the list, then come back here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: 1. Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 34) {
            Spacer(minLength: 0)
            HStack(spacing: 22) {
                BigKey(symbol: "sparkle", legend: "caps lock", accent: Accent.hyper, lit: false, size: 120)
                BigKey(symbol: "moon.fill", legend: "right ⌘", accent: Accent.meh, lit: false, size: 120)
            }
            StepHeader(eyebrow: "Welcome to Superkeys",
                       title: "Two private keys for your Mac.",
                       detail: "Caps Lock becomes ✦ Hyper and right ⌘ becomes ☾ Meh. Hold one and the rest of your keyboard opens apps, arranges windows and switches desktops. Neither ever types a thing.")
            Spacer(minLength: 0)
        }
    }
}

// MARK: 2. Accessibility

private struct AccessStep: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill((state.accessibilityTrusted ? Color.green : Accent.meh).opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: state.accessibilityTrusted ? "checkmark" : "accessibility")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(state.accessibilityTrusted ? Color.green : Accent.meh)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.easeOut(duration: 0.25), value: state.accessibilityTrusted)
            StepHeader(eyebrow: "Step 1 · Permission",
                       title: state.accessibilityTrusted ? "You're all set." : "Let Superkeys see the two keys.",
                       detail: state.accessibilityTrusted
                           ? "Accessibility is on. Superkeys can now use Caps Lock and right ⌘, and move your windows."
                           : "macOS asks you to allow Accessibility. Superkeys uses it to notice Caps Lock and right ⌘ and to move windows. It never records what you type.")
            if !state.accessibilityTrusted {
                VStack(spacing: 10) {
                    Button {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    } label: {
                        Label("Open Accessibility Settings", systemImage: "arrow.up.forward.app")
                    }
                    .controlSize(.large)
                    Text("Switch on Superkeys in the list. This page moves on by itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: 3. Try ✦

private struct TryHyperStep: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var indicator = HyperIndicator.shared
    @AppStorage("triedHyperKey") private var tried = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            KeyboardRow.capsLock(held: indicator.held)
            if state.accessibilityTrusted {
                StepHeader(eyebrow: "Step 2 · Try it",
                           title: tried ? "That's ✦ Hyper." : "Hold Caps Lock.",
                           detail: tried
                               ? "Keep holding for a moment and a panel lists everything ✦ does. ✦ ← and ✦ → snap a window; ✦ ↑ arranges them all."
                               : "Press and hold it now, on the left of your keyboard. The key above lights up when Superkeys sees it.")
            } else {
                StepHeader(eyebrow: "Step 2 · Try it",
                           title: "Caps Lock becomes ✦ Hyper.",
                           detail: "Superkeys needs Accessibility turned on before it can see the key. Turn it on and try it here.")
                NeedsAccess()
            }
            Spacer(minLength: 0)
        }
        .onChange(of: indicator.held) { _, held in
            if held { tried = true }
        }
    }
}

// MARK: 4. First app keys

/// An app this Mac uses a lot, offered a key in the tour.
private struct Suggestion: Identifiable {
    let bundleID: String
    let name: String
    let url: URL
    var id: String { bundleID }
}

/// The suggestions, kept by the tour so its main button can add them.
/// Each ticked app gets its first letter, or the next free number when the
/// letter is taken; keys are handed out again whenever the ticks change, in
/// order of use, so the most-used app keeps the letter.
@MainActor
private final class AppPicks: ObservableObject {
    @Published private(set) var suggestions: [Suggestion] = []
    @Published var chosen: Set<String> = [] { didSet { assignKeys() } }
    @Published private(set) var keys: [String: (label: String, keyCode: Int)] = [:]
    private var loaded = false

    private static let maximum = 8
    private static let preselected = 4
    private static let numbers = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    func load() {
        guard !loaded else { return }
        loaded = true
        suggestions = Array(Self.mostUsedApps().prefix(Self.maximum))
        chosen = Set(suggestions.prefix(Self.preselected).map(\.bundleID))
    }

    func label(for app: Suggestion) -> String { keys[app.bundleID]?.label ?? "" }

    func add() {
        for app in suggestions where chosen.contains(app.bundleID) {
            guard let key = keys[app.bundleID] else { continue }
            _ = BindingsStore.shared.add(keyCode: key.keyCode, label: key.label, bundleID: app.bundleID, name: app.name)
        }
        // Added once; going Back shows what's left rather than adding twice.
        suggestions.removeAll { chosen.contains($0.bundleID) }
        chosen = []
    }

    /// Ticked apps first, so they get the letters, then the rest, so an
    /// unticked row shows the key it would get.
    private func assignKeys() {
        let store = BindingsStore.shared
        var used = Set<Int>()
        func free(_ label: String) -> Int? {
            guard let code = KeyCodes.keyCode(forLabel: label), !used.contains(code),
                  store.validate(keyCode: code, replacing: nil) == nil else { return nil }
            return code
        }
        var result: [String: (label: String, keyCode: Int)] = [:]
        let ordered = suggestions.filter { chosen.contains($0.bundleID) } + suggestions.filter { !chosen.contains($0.bundleID) }
        for app in ordered {
            let letter = app.name.uppercased().first(where: { ("A"..."Z").contains(String($0)) }).map(String.init)
            let label = [letter].compactMap { $0 }.first(where: { free($0) != nil })
                ?? Self.numbers.first(where: { free($0) != nil })
            guard let label, let code = free(label) else { continue }
            used.insert(code)
            result[app.bundleID] = (label, code)
        }
        keys = result
    }

    /// Apps ranked by how often they've been opened (Spotlight keeps the
    /// count), then the Dock and whatever is running, for a Mac with little
    /// history. Skips apps that already have a key, menu-bar-only helpers,
    /// System Settings and Superkeys itself.
    private static func mostUsedApps() -> [Suggestion] {
        var seen = Set(BindingsStore.shared.bindings.map(\.bundleID))
        seen.formUnion(["com.apple.systempreferences", "com.apple.finder", Bundle.main.bundleIdentifier ?? "",
                        "space.superkeys", "space.superkeys.dev"])
        var result: [Suggestion] = []
        func consider(_ bundleID: String?, url knownURL: URL? = nil) {
            guard let bundleID, !seen.contains(bundleID) else { return }
            seen.insert(bundleID)
            guard let url = knownURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            if (info?["LSUIElement"] as? Bool) == true || (info?["LSUIElement"] as? String) == "1" { return }
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            result.append(Suggestion(bundleID: bundleID, name: name, url: url))
        }
        for (bundleID, url) in spotlightRanking() { consider(bundleID, url: url) }
        let dock = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        for tile in dock { consider((tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String) }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            consider(app.bundleIdentifier, url: app.bundleURL)
        }
        return result
    }

    private static func spotlightRanking() -> [(String, URL)] {
        let query = "kMDItemContentType == 'com.apple.application-bundle' && kMDItemUseCount > 0"
        guard let q = MDQueryCreate(nil, query as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(q, ["/Applications", "/System/Applications",
                                  NSHomeDirectory() + "/Applications"] as CFArray, 0)
        guard MDQueryExecute(q, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        let recent = Date().addingTimeInterval(-60 * 24 * 3600)
        var rows: [(count: Int, id: String, url: URL)] = []
        for i in 0..<MDQueryGetResultCount(q) {
            guard let raw = MDQueryGetResultAtIndex(q, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  let id = MDItemCopyAttribute(item, kMDItemCFBundleIdentifier) as? String,
                  let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date, last > recent
            else { continue }
            let count = MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? Int ?? 0
            rows.append((count, id, URL(fileURLWithPath: path)))
        }
        return rows.sorted { $0.count > $1.count }.map { ($0.id, $0.url) }
    }
}

private struct AppsStep: View {
    @ObservedObject var picks: AppPicks
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(eyebrow: "Step 3 · Your apps",
                       title: "One key per app.",
                       detail: "Hold ✦ and press the key: the app opens, or comes forward. These are the apps you use most, each on its first letter. Change them any time in Settings.")
            if picks.suggestions.isEmpty {
                Text("Every app you use already has a key. Add more any time in Settings → Shortcuts.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(picks.suggestions) { app in tile(app) }
                }
            }
            // Groups: the answer to running out of letters.
            HStack(spacing: 10) {
                SequenceCombo(label: "O", then: "P")
                Text("Out of letters? Make a group: \(Glyph.hyper) O then P for 1Password, \(Glyph.hyper) O then S for Slack. Set them up in Settings → Shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            Spacer(minLength: 0)
        }
        .onAppear(perform: picks.load)
    }

    private func tile(_ app: Suggestion) -> some View {
        let on = picks.chosen.contains(app.bundleID)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return Button {
            if on { picks.chosen.remove(app.bundleID) } else { picks.chosen.insert(app.bundleID) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(on ? Accent.hyper : Color.secondary.opacity(0.6))
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 26, height: 26)
                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                KeyCombo(keys: [Glyph.hyper, picks.label(for: app)])
                    .opacity(on ? 1 : 0.45)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(shape.fill(on ? Accent.hyper.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(shape.stroke(on ? Accent.hyper.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityHint("Hyper \(picks.label(for: app)) opens \(app.name)")
    }
}

// MARK: 5. Try ☾

private struct MehStep: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var indicator = HyperIndicator.shared
    @State private var tried = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            KeyboardRow.rightCommand(held: indicator.meh)
            if state.accessibilityTrusted {
                StepHeader(eyebrow: "Step 4 · Try it",
                           title: tried ? "That's ☾ Meh." : "Hold right ⌘.",
                           detail: tried
                               ? "☾ 1–9 switch desktops, adding any you don't have yet. ☾ ⇧ 1–9 takes the window with you, and hold ☾ for a moment to see the rest."
                               : "The one to the right of the space bar, not the left. The key above lights up when Superkeys sees it.")
            } else {
                StepHeader(eyebrow: "Step 4 · Try it",
                           title: "Right ⌘ becomes ☾ Meh.",
                           detail: "The one to the right of the space bar, for desktops: ☾ 1–9 switch between them. It works once Accessibility is on.")
                NeedsAccess()
            }
            Spacer(minLength: 0)
        }
        .onChange(of: indicator.meh) { _, held in
            if held { tried = true }
        }
    }
}

// MARK: 6. Keystrokes

/// The terminal set, less any key the apps step just took.
@MainActor
private final class KeystrokePicks: ObservableObject {
    struct Offer: Identifiable {
        let stroke: Keystroke
        let purpose: String
        /// Why it can't be added, when the key is already used.
        let taken: String?
        var id: String { stroke.id }
    }

    @Published private(set) var offers: [Offer] = []
    @Published var chosen: Set<String> = []

    /// Called each time the step shows, since going Back to the apps step can
    /// change which keys are free.
    func refresh() {
        offers = Keystroke.terminalSet.map { item in
            Offer(stroke: item.stroke, purpose: item.purpose,
                  taken: BindingsStore.shared.validate(keyCode: item.stroke.keyCode, replacing: nil))
        }
        chosen = Set(offers.filter { $0.taken == nil }.map(\.id))
    }

    func add() {
        for offer in offers where chosen.contains(offer.id) {
            _ = BindingsStore.shared.add(offer.stroke)
        }
        chosen = []
    }
}

private struct KeystrokesStep: View {
    @ObservedObject var picks: KeystrokePicks
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(eyebrow: "Step 5 · Keystrokes",
                       title: "✦ can be Control, too.",
                       detail: "Hold ✦ and press a key to send a key combination to the app in front. Caps Lock is easier to reach than ⌃, which is handy in the terminal:")
            VStack(spacing: 8) {
                ForEach(picks.offers) { offer in row(offer) }
            }
            .frame(maxWidth: 480)
            Text("Add any combination later in Settings → Shortcuts, such as ✦ W → ⌘ ⇧ T.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Toggle("Open Superkeys at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Open Superkeys at login")
        }
        .onAppear(perform: picks.refresh)
    }

    private func row(_ offer: KeystrokePicks.Offer) -> some View {
        let on = picks.chosen.contains(offer.id)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return Button {
            if on { picks.chosen.remove(offer.id) } else { picks.chosen.insert(offer.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: offer.taken != nil ? "minus.circle" : on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(on ? Accent.hyper : Color.secondary.opacity(0.6))
                KeyCombo(keys: [Glyph.hyper, offer.stroke.label])
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                KeyCombo(keys: offer.stroke.sendKeys)
                VStack(alignment: .leading, spacing: 1) {
                    Text(offer.purpose).font(.system(size: 13))
                    if let taken = offer.taken {
                        Text(taken).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(shape.fill(on ? Accent.hyper.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(shape.stroke(on ? Accent.hyper.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1))
            .opacity(offer.taken != nil ? 0.55 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(offer.taken != nil)
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityLabel("Hyper \(offer.stroke.label) sends Control \(offer.stroke.sendLabel): \(offer.purpose)")
    }
}
