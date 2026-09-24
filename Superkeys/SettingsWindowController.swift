import AppKit
import Combine
import SwiftUI

/// The settings window, built in AppKit so it gets native toolbar tabs and
/// can be opened from anywhere. Superkeys lives in the menu bar; its Dock icon
/// only shows while this window is open.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    enum Pane: Int {
        case general, shortcuts, permissions
    }

    private let tabs = NSTabViewController()
    private var sizing: Set<AnyCancellable> = []
    /// Each tab fits its content until the window is resized by hand or by a
    /// snap or arrange; then it keeps that size until it is closed.
    private var fitsContent = true

    private init() {
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 520, height: 260)
        window.isRestorable = false
        super.init(window: window)

        // Each pane gets the height its content needs; the window resizes as
        // you switch, like other macOS settings windows.
        tabs.addTabViewItem(Self.item("General", symbol: "slider.horizontal.3", height: Self.generalHeight,
                                      GeneralTab(showShortcuts: { [weak self] in self?.select(.shortcuts) })))
        let shortcuts = Self.item("Shortcuts", symbol: "keyboard", height: 440, ShortcutsTab())
        tabs.addTabViewItem(shortcuts)
        let permissions = Self.item("Permissions", symbol: "lock.shield", height: 260, PermissionsTab())
        tabs.addTabViewItem(permissions)
        window.delegate = self
        window.center()

        // The app list grows with every shortcut, and Permissions gains a row
        // when the keys can't start, so those panes follow their content.
        BindingsStore.shared.$bindings.sink { [weak self, weak shortcuts] bindings in
            guard self?.fitsContent != false else { return }
            shortcuts?.viewController?.preferredContentSize =
                NSSize(width: Self.paneWidth, height: Self.shortcutsHeight(rows: bindings.count))
        }.store(in: &sizing)
        AppState.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak permissions] _ in
            guard self?.fitsContent != false else { return }
            let extraRow = AppState.shared.status == .unavailable
            permissions?.viewController?.preferredContentSize =
                NSSize(width: Self.paneWidth, height: extraRow ? 330 : 260)
        }.store(in: &sizing)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private static let paneWidth: CGFloat = 700
    private static let generalHeight: CGFloat = 790

    private static func shortcutsHeight(rows: Int) -> CGFloat {
        rows == 0 ? 300 : min(620, max(240, 162 + CGFloat(rows) * 42))
    }

    private static func item<Content: View>(
        _ label: String, symbol: String, height: CGFloat, _ content: Content
    ) -> NSTabViewItem {
        let host = NSHostingController(rootView: content
            .environmentObject(AppState.shared)
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity))
        // The tab controller sizes the window from this and titles it from the
        // selected pane.
        host.preferredContentSize = NSSize(width: paneWidth, height: height)
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func select(_ pane: Pane) {
        tabs.selectedTabViewItemIndex = pane.rawValue
    }

    /// Stop fitting each tab and hold the window at its current size, so a
    /// snapped or arranged Settings window stays in its slot when you switch
    /// tabs.
    func keepCurrentSize() {
        guard let window else { return }
        fitsContent = false
        let size = window.contentLayoutRect.size
        for item in tabs.tabViewItems {
            item.viewController?.preferredContentSize = size
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        keepCurrentSize()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Next time it opens, each tab fits its content again.
        fitsContent = true
        let heights: [CGFloat] = [Self.generalHeight,
                                  Self.shortcutsHeight(rows: BindingsStore.shared.bindings.count),
                                  AppState.shared.status == .unavailable ? 330 : 260]
        for (item, height) in zip(tabs.tabViewItems, heights) {
            item.viewController?.preferredContentSize = NSSize(width: Self.paneWidth, height: height)
        }
    }
}
