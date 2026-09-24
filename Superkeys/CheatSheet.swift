import AppKit
import SwiftUI

/// Hold ✦ or ☾ for a moment without pressing anything and a panel lists what
/// that key does. It never takes focus, and it goes away the moment the key is
/// released or a chord is pressed.
@MainActor
final class CheatSheet {
    static let shared = CheatSheet()

    enum Layer { case hyper, meh }

    private static let delay: TimeInterval = 0.6

    private var pending: DispatchWorkItem?
    private var panel: NSPanel?

    func pressed(_ layer: Layer) {
        pending?.cancel()
        guard AppState.shared.showCheatSheet else { return }
        let work = DispatchWorkItem { [weak self] in self?.show(layer) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
    }

    /// A chord or a release both mean the key was used, not browsed.
    func dismiss() {
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
    }

    private func show(_ layer: Layer) {
        let desktops = SpaceManager.shared.desktopSummary()
        let content = CheatSheetView(
            layer: layer,
            apps: BindingsStore.shared.bindings.sorted { $0.label < $1.label },
            desktopCount: desktops.count,
            currentDesktop: desktops.current
        )
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = host

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Dark glass keeps the white text readable over any wallpaper.
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

private struct CheatSheetView: View {
    let layer: CheatSheet.Layer
    let apps: [BoundApp]
    let desktopCount: Int
    let currentDesktop: Int?

    private var accent: Color { layer == .hyper ? Accent.hyper : Accent.meh }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: Glyph.symbol(for: layer == .hyper ? Glyph.hyper : Glyph.meh) ?? "questionmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Accent.gradient(accent)))
                    .shadow(color: accent.opacity(0.5), radius: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(layer == .hyper ? "Hyper" : "Meh").font(.headline)
                    Text(layer == .hyper ? "Windows and apps" : "Desktops")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if layer == .hyper { hyper } else { meh }
        }
        .padding(20)
        .frame(width: 390, alignment: .leading)
        .background {
            GlassBackground(tint: NSColor(accent).withAlphaComponent(0.18), cornerRadius: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// One grid for every row, so chords of any length line up and never
    /// touch their labels.
    @ViewBuilder private var hyper: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            row([Glyph.hyper, "←", "→"], "Snap left or right")
            row([Glyph.hyper, "↩"], "Fill the screen, again to restore")
            row([Glyph.hyper, "↑"], "Arrange the windows here")
            row([Glyph.hyper, "⇧", "←↑↓→"], "Swap with the next window")
            GridRow {
                Divider().opacity(0.5).gridCellColumns(2).padding(.vertical, 4)
            }
            if apps.isEmpty {
                GridRow {
                    Text("No apps assigned yet. Add them in Settings → Shortcuts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .gridCellColumns(2)
                }
            } else {
                ForEach(apps) { app in
                    GridRow {
                        KeyCombo(keys: [Glyph.hyper, app.label])
                        HStack(spacing: 8) {
                            if let icon = AppCatalog.shared.icon(for: app.bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(app.name)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var meh: some View {
        if desktopCount > 0 {
            HStack(spacing: 6) {
                ForEach(1...desktopCount, id: \.self) { number in
                    let current = number == currentDesktop
                    Text("\(number)")
                        .font(.system(size: 13, weight: current ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(current ? 1 : 0.85))
                        .frame(width: 30, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(current ? AnyShapeStyle(Accent.gradient(accent)) : AnyShapeStyle(Color.white.opacity(0.1))))
                }
            }
            .accessibilityLabel("Desktop \(currentDesktop ?? 0) of \(desktopCount)")
        }
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            row([Glyph.meh, "1–9"], "Switch to that desktop")
            row([Glyph.meh, "⇧", "1–9"], "Move the window there")
            row([Glyph.meh, "right ⌥"], "Flip back to the last one")
        }
    }

    private func row(_ keys: [String], _ text: String) -> some View {
        GridRow {
            KeyCombo(keys: keys)
            Text(text)
        }
    }
}
