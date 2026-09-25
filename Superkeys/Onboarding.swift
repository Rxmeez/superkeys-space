import AppKit
import SwiftUI

/// A short, hands-on setup: five steps, each of which waits for you to do the
/// thing rather than describing it. Shown once to new users; "Welcome Tour…"
/// in the menu and General bring it back.
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

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.title = "Welcome to Superkeys"
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: OnboardingView(finish: { [weak self] in
            self?.close()
        }).environmentObject(AppState.shared))
        window.setContentSize(NSSize(width: 620, height: 520))
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
    case welcome, access, tryHyper, apps, finish
}

private struct OnboardingView: View {
    let finish: () -> Void
    @EnvironmentObject private var state: AppState
    @StateObject private var picks = AppPicks()
    @State private var step: Step = {
        #if DEBUG
        return Step(rawValue: OnboardingWindowController.debugStartStep) ?? .welcome
        #else
        return .welcome
        #endif
    }()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .access: AccessStep()
                case .tryHyper: TryHyperStep()
                case .apps: AppsStep(picks: picks)
                case .finish: FinishStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 44)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            footer
        }
        .frame(width: 620, height: 520)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { advance() }
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Accent.hyper : Color.secondary.opacity(0.3))
                        .frame(width: s == step ? 18 : 7, height: 7)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            if step != .welcome && step != .finish {
                Button("Back") { move(-1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
            }
            primaryButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { advance() }.keyboardShortcut(.defaultAction).controlSize(.large)
        case .access:
            Button(state.accessibilityTrusted ? "Continue" : "Skip for Now") { advance() }
                .keyboardShortcut(state.accessibilityTrusted ? .defaultAction : nil)
                .controlSize(.large)
        case .tryHyper:
            Button("Continue") { advance() }.keyboardShortcut(.defaultAction).controlSize(.large)
        case .apps:
            Button(picks.chosen.isEmpty ? "Skip" : "Add \(picks.chosen.count) \(picks.chosen.count == 1 ? "Key" : "Keys")") {
                picks.add()
                advance()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        case .finish:
            Button("Done") { finish() }.keyboardShortcut(.defaultAction).controlSize(.large)
        }
    }

    private func advance() { move(1) }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
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
    @ObservedObject private var indicator = HyperIndicator.shared
    @AppStorage("triedHyperKey") private var tried = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            BigKey(symbol: "sparkle", legend: "caps lock", accent: Accent.hyper, lit: indicator.held, size: 130)
            StepHeader(eyebrow: "Step 2 · Try it",
                       title: tried ? "That's ✦ Hyper." : "Hold Caps Lock.",
                       detail: tried
                           ? "Keep holding for a moment and a panel lists everything ✦ does. ✦ ← and ✦ → snap a window; ✦ ↑ arranges them all."
                           : "Press and hold it now. The key above lights up when Superkeys sees it.")
            Spacer(minLength: 0)
        }
        .onChange(of: indicator.held) { _, held in
            if held { tried = true }
        }
    }
}

// MARK: 4. First app keys

/// An app Superkeys found on this Mac and a key to suggest for it.
private struct Suggestion: Identifiable {
    let bundleID: String
    let name: String
    let url: URL
    let label: String
    let keyCode: Int
    var id: String { bundleID }
}

/// The suggestions, kept by the tour so its main button can add them.
@MainActor
private final class AppPicks: ObservableObject {
    @Published var suggestions: [Suggestion] = []
    @Published var chosen: Set<String> = []
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        var found: [Suggestion] = []
        let store = BindingsStore.shared
        func consider(_ bundleIDs: [String], label: String, keyCode: Int) {
            guard store.validate(keyCode: keyCode, replacing: nil) == nil else { return }
            for id in bundleIDs where !store.bindings.contains(where: { $0.bundleID == id }) {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
                var name = FileManager.default.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                found.append(Suggestion(bundleID: id, name: name, url: url, label: label, keyCode: keyCode))
                return
            }
        }
        let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://superkeys.space")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        consider([browser, "com.apple.Safari"].compactMap { $0 }, label: "B", keyCode: 11)
        consider(["com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
                  "com.github.wez.wezterm", "com.apple.Terminal"], label: "T", keyCode: 17)
        consider(["com.apple.Notes"], label: "N", keyCode: 45)
        consider(["com.microsoft.VSCode", "dev.zed.Zed", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode"],
                 label: "E", keyCode: 14)
        suggestions = found
        chosen = Set(found.map(\.bundleID))
    }

    func add() {
        for app in suggestions where chosen.contains(app.bundleID) {
            _ = BindingsStore.shared.add(keyCode: app.keyCode, label: app.label, bundleID: app.bundleID, name: app.name)
        }
        // Added once; going Back shows what's left rather than adding twice.
        suggestions.removeAll { chosen.contains($0.bundleID) }
        chosen = []
    }
}

private struct AppsStep: View {
    @ObservedObject var picks: AppPicks

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(eyebrow: "Step 3 · Your apps",
                       title: "One key per app.",
                       detail: "Hold ✦ and press a key: the app opens, or comes forward. Here are some to start with; change or add more any time in Settings.")
            if picks.suggestions.isEmpty {
                Text("Add your own any time in Settings → Shortcuts.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(picks.suggestions) { app in
                        Toggle(isOn: Binding(
                            get: { picks.chosen.contains(app.bundleID) },
                            set: { on in if on { picks.chosen.insert(app.bundleID) } else { picks.chosen.remove(app.bundleID) } }
                        )) {
                            HStack(spacing: 12) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable().frame(width: 26, height: 26)
                                Text(app.name).font(.system(size: 14))
                                Spacer()
                                KeyCombo(keys: [Glyph.hyper, app.label])
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                    }
                }
                .frame(maxWidth: 400)
            }
            Spacer(minLength: 0)
        }
        .onAppear(perform: picks.load)
    }
}

// MARK: 5. Try ☾ and finish

private struct FinishStep: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var indicator = HyperIndicator.shared

    var body: some View {
        VStack(spacing: 22) {
            BigKey(symbol: "moon.fill", legend: "right ⌘", accent: Accent.meh, lit: indicator.meh, size: 96)
            StepHeader(eyebrow: "Step 4 · Desktops",
                       title: "And ☾ is for desktops.",
                       detail: "Hold right ⌘ and press 2 to go to Desktop 2; it's created if you don't have one. Right ⌘ with right ⌥ flips back.")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                chord([Glyph.hyper, "←", "→"], "Snap a window")
                chord([Glyph.hyper, "↑"], "Arrange the windows on this screen")
                chord([Glyph.meh, "1–9"], "Switch desktop")
                chord([Glyph.meh, "⇧", "1–9"], "Send the window to a desktop")
            }
            .font(.system(size: 13))
            Toggle("Open Superkeys at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            Spacer(minLength: 0)
        }
    }

    private func chord(_ keys: [String], _ text: String) -> some View {
        GridRow {
            KeyCombo(keys: keys)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
