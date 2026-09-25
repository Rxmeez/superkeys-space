import SwiftUI

// MARK: - General

struct GeneralTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { !state.paused },
                    set: { state.setPaused(!$0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hyper and Meh keys")
                        Text(state.paused
                             ? "Paused. Caps Lock and right ⌘ work as normal."
                             : "✦ Caps Lock and ☾ right ⌘. Neither types, locks, or reaches other apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Hyper and Meh keys")

                if state.status == .needsAccess || state.status == .unavailable {
                    SetupNotice()
                }
                if state.status == .on {
                    TryItRow()
                }
            }

            Section {
                Toggle(isOn: $state.showCheatSheet) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show chords while a key is held")
                        Text("Hold \(Glyph.hyper) or \(Glyph.meh) for a moment without pressing anything.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Show chords while a key is held")
                Toggle("Open at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .accessibilityLabel("Open at login")
            }

            Section {
                UpdatesRow()
            }

            Section {
                LabeledContent {
                    Button("Take the Tour") { OnboardingWindowController.show() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome tour")
                        Text("A short, hands-on walk through the two keys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Keys

/// Everything the two keys do, for reference.
struct KeysTab: View {

    var body: some View {
        Form {
            Section {
                LayerKeyRow(layer: .hyper, title: "Hyper Key", detail: "Hold Caps Lock. Apps and windows.")
                ChordRow(keys: [Glyph.hyper, "key"], detail: "Open an app, or send a keystroke such as ⌃ C")
                ChordRow(keys: [Glyph.hyper, "←", "→"], detail: "Snap to the left or right half; again for the next display")
                ChordRow(keys: [Glyph.hyper, "⌥", "←", "→"], detail: "Move the window to the next display as it is")
                ChordRow(keys: [Glyph.hyper, "↩"], detail: "Fill the screen; again to restore")
                ChordRow(keys: [Glyph.hyper, "↑"], detail: "Arrange up to 4 windows on this screen; again to undo")
                ChordRow(keys: [Glyph.hyper, "⇧", "←↑↓→"], detail: "Swap the window with the one next to it")
            }

            Section {
                LayerKeyRow(layer: .meh, title: "Meh Key", detail: "Hold right ⌘. Desktops.")
                ChordRow(keys: [Glyph.meh, "1–9"], detail: "Switch to that desktop, adding it if needed")
                ChordRow(keys: [Glyph.meh, "⇧", "1–9"], detail: "Move the window there and follow it")
                ChordRow(keys: [Glyph.meh, "right ⌥"], detail: "Flip back to the previous desktop")
            } footer: {
                Text("With more than one display, ☾ acts on the display under the pointer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shown once setup works: asks you to hold Caps Lock, then confirms it the
/// first time you do. Once confirmed it never shows again.
private struct TryItRow: View {
    @ObservedObject private var indicator = HyperIndicator.shared
    @AppStorage("triedHyperKey") private var tried = false
    @State private var confirmedNow = false

    var body: some View {
        if !tried || confirmedNow {
            HStack(spacing: 12) {
                Image(systemName: Glyph.symbol(for: Glyph.hyper) ?? "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(confirmedNow || indicator.held ? Color.white : Accent.hyper)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(
                        confirmedNow || indicator.held ? AnyShapeStyle(Accent.gradient(Accent.hyper))
                                                        : AnyShapeStyle(Accent.hyper.opacity(0.14))))
                    .animation(.easeOut(duration: 0.12), value: indicator.held)
                VStack(alignment: .leading, spacing: 2) {
                    Text(confirmedNow ? "You're set" : "Try it: hold Caps Lock")
                    Text(confirmedNow ? "The Hyper Key works. Keep holding for a moment to see everything it does."
                                      : "It lights up here when Superkeys sees it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: indicator.held) { _, held in
                if held, !tried {
                    tried = true
                    confirmedNow = true
                }
            }
        }
    }
}

/// Version, with a manual check beside it, and automatic updates.
private struct UpdatesRow: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if Updater.isEnabled {
            LabeledContent("Version \(Updater.version)") {
                HStack {
                    WhatsNewButton()
                    Button("Check for Updates") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            Toggle(isOn: $updater.checksAutomatically) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install updates automatically")
                    Text("Checked once a day. Your keys keep working through updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Install updates automatically")
        } else {
            LabeledContent("Version \(Updater.version)") { WhatsNewButton() }
        }
    }
}

/// The notes for this version, with a dot after an update until they're read.
private struct WhatsNewButton: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button {
            WhatsNew.show()
        } label: {
            HStack(spacing: 5) {
                if WhatsNew.pending != nil {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                }
                Text("What's New")
            }
        }
        .accessibilityValue(WhatsNew.pending != nil ? "Unread" : "")
    }
}

/// One layer key with a large keycap that lights up while it is held.
private struct LayerKeyRow: View {
    enum Layer { case hyper, meh }

    let layer: Layer
    let title: String
    let detail: String
    @ObservedObject private var indicator = HyperIndicator.shared

    private var held: Bool { layer == .hyper ? indicator.held : indicator.meh }

    private var accent: Color { layer == .hyper ? Accent.hyper : Accent.meh }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Glyph.symbol(for: layer == .hyper ? Glyph.hyper : Glyph.meh) ?? "questionmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(held ? Color.white : accent)
                .frame(width: 38, height: 38)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(nsColor: .controlBackgroundColor))
                        RoundedRectangle(cornerRadius: 9)
                            .fill(held ? AnyShapeStyle(Accent.gradient(accent)) : AnyShapeStyle(accent.opacity(0.12)))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(accent.opacity(held ? 0 : 0.35), lineWidth: 1)
                )
                .shadow(color: accent.opacity(held ? 0.55 : 0), radius: 8)
                .animation(.easeOut(duration: 0.12), value: held)
                .accessibilityLabel(held ? "\(title), held" : title)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

private struct SetupNotice: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        switch state.status {
        case .needsAccess:
            VStack(alignment: .leading, spacing: 8) {
                notice("Superkeys needs Accessibility access before it can use Caps Lock.", symbol: "lock") {
                    Button("Open Settings…") { Permissions.openAccessibilitySettings() }
                }
                HStack(spacing: 10) {
                    Text("Switch already on? macOS is holding an old entry. Reset it, then switch Superkeys on again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Reset Access…") { Permissions.resetAccessibility() }
                        .controlSize(.small)
                }
                .padding(.leading, 26)
            }
        case .unavailable:
            notice("The Hyper Key couldn't start. Some Macs also need Input Monitoring.",
                   symbol: "exclamationmark.triangle") {
                HStack {
                    Button("Input Monitoring…") { Permissions.openInputMonitoringSettings() }
                    Button("Try Again") { state.restart() }
                }
            }
        case .on, .paused:
            EmptyView()
        }
    }

    private func notice<Action: View>(
        _ text: String, symbol: String, @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            action()
        }
    }
}

private struct ChordRow<Accessory: View>: View {
    let keys: [String]
    let detail: String
    let accessory: Accessory

    init(keys: [String], detail: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.keys = keys
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        LabeledContent(detail) {
            HStack(spacing: 10) {
                accessory
                KeyCombo(keys: keys)
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "Reads the Hyper and Meh keys and moves windows.",
                    granted: state.accessibilityTrusted,
                    grantedTitle: "Allowed",
                    actionTitle: "Open Settings…",
                    action: Permissions.openAccessibilitySettings
                )
                PermissionRow(
                    symbol: "rectangle.3.group",
                    title: "Desktop shortcuts",
                    detail: "macOS's own Switch to Desktop shortcuts, used to change and move between desktops.",
                    granted: state.desktopShortcutsEnabled,
                    grantedTitle: "On",
                    actionTitle: "Turn On",
                    action: {
                        MissionControlShortcuts.enable()
                        state.reconcile()
                    }
                )
                if state.multipleDisplays {
                    PermissionRow(
                        symbol: "display.2",
                        title: "Separate desktops per display",
                        detail: "\"Displays have separate Spaces\" gives each display its own desktops, so ☾ 1–9 act on the display under the pointer. Takes effect after logging out.",
                        granted: state.separateSpaces,
                        grantedTitle: "On",
                        actionTitle: "Open Settings…",
                        action: Permissions.openDesktopAndDockSettings
                    )
                }
                if state.status == .unavailable {
                    PermissionRow(
                        symbol: "keyboard",
                        title: "Input Monitoring",
                        detail: "Some Macs need this too before the Hyper Key can start.",
                        granted: false,
                        grantedTitle: "Allowed",
                        actionTitle: "Open Settings…",
                        action: Permissions.openInputMonitoringSettings
                    )
                }
            } footer: {
                Text("Superkeys never records what you type. Keys pass straight through unless the Hyper or Meh key is held.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let grantedTitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if granted {
                Label(grantedTitle, systemImage: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button(actionTitle, action: action)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Advanced

struct AdvancedTab: View {
    @ObservedObject private var config = ConfigSync.shared
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        Button("Show in Finder") { config.revealInFinder() }
                        Button("Open") { config.open() }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Config file")
                        Text(config.displayPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if config.problems.isEmpty {
                    Label("In step with Settings", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(config.notApplied ? "Not applied: fix the file and save it again"
                                                : "Applied, except for these lines",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        ForEach(config.problems.prefix(6)) { problem in
                            Text("Line \(problem.line): \(problem.message)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } footer: {
                Text("Your app keys and preferences as a text file. Edit it in any editor and Superkeys applies it when you save; changes made here are written back. Keep it in your dotfiles to carry your setup to another Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent {
                    Button("Reset Access…") { Permissions.resetAccessibility() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility looks on but the keys don't work")
                        Text("Clears the old entry macOS keeps, so you can switch Superkeys on again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
