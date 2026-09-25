import SwiftUI

// MARK: - General

struct GeneralTab: View {
    @EnvironmentObject private var state: AppState
    let showShortcuts: () -> Void

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
                             : "Neither key types, locks, or reaches other apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if state.status == .needsAccess || state.status == .unavailable {
                    SetupNotice()
                }
                if state.status == .on {
                    TryItRow()
                }
            } footer: {
                if !state.lastAction.isEmpty {
                    Text("Last action: \(state.lastAction)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LayerKeyRow(layer: .hyper, title: "Hyper Key", detail: "Hold Caps Lock")
                ChordRow(keys: [Glyph.hyper, "←", "→"], detail: "Snap to the left or right half. Again to move to the next display")
                ChordRow(keys: [Glyph.hyper, "⌥", "←", "→"], detail: "Move the window to the next display as it is")
                ChordRow(keys: [Glyph.hyper, "↩"], detail: "Fill the screen. Press again to restore")
                ChordRow(keys: [Glyph.hyper, "↑"], detail: "Arrange up to 4 windows on this screen. Again to undo")
                ChordRow(keys: [Glyph.hyper, "⇧", "←↑↓→"], detail: "Swap the window with the one next to it")
                LabeledContent("Open an app you've assigned") {
                    HStack(spacing: 10) {
                        Button("Edit Apps…", action: showShortcuts)
                            .buttonStyle(.link)
                        KeyCombo(keys: [Glyph.hyper, "key"])
                    }
                }
            }

            Section {
                LayerKeyRow(layer: .meh, title: "Meh Key", detail: "Hold right ⌘")
                ChordRow(keys: [Glyph.meh, "1–9"], detail: "Switch to that desktop on the display under the pointer")
                ChordRow(keys: [Glyph.meh, "⇧", "1–9"], detail: "Move the window there and follow it")
                ChordRow(keys: [Glyph.meh, "right ⌥"], detail: "Flip back to the previous desktop")
            } footer: {
                Text("Desktops that don't exist yet are created for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Toggle("Open at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                UpdatesRow()
                LabeledContent {
                    HStack {
                        Button("Import…") { SettingsTransfer.importFile() }
                        Button("Export…") { SettingsTransfer.export() }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings file")
                        Text("Your app shortcuts and preferences as JSON, to back up, edit, or move to another Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

/// Version, automatic update checks, and a manual check.
private struct UpdatesRow: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if Updater.isEnabled {
            Toggle(isOn: $updater.checksAutomatically) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep Superkeys up to date")
                    Text("Version \(Updater.version). New versions install in the background, and your keys keep working.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            LabeledContent("Check for a new version now") {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        } else {
            LabeledContent("Version", value: Updater.version)
        }
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

private struct ChordRow: View {
    let keys: [String]
    let detail: String

    var body: some View {
        LabeledContent(detail) {
            KeyCombo(keys: keys)
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
