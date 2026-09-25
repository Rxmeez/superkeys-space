import OSLog
import SwiftUI

@main
struct SuperkeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var hyper = HyperIndicator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(AppState.shared)
        } label: {
            Image(nsImage: menuBarImage)
                .accessibilityLabel("Superkeys")
        }
    }

    /// The logo is both keys in one mark: a moon with stars. Holding ✦ lights
    /// the stars amber, holding ☾ lights the moon indigo. At rest it is a
    /// plain template icon like the rest of the menu bar.
    private var menuBarImage: NSImage {
        if let badge = hyper.alertBadge {
            return Self.alertImage(badge: badge, offset: hyper.shakeOffset)
        }
        let base = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "Superkeys") ?? NSImage()
        guard hyper.held || hyper.meh else {
            base.isTemplate = true
            return base
        }
        // Palette layers for moon.stars: the moon first, then the stars.
        let moon = hyper.meh ? NSColor(Accent.meh) : .labelColor
        let stars = hyper.held && !hyper.meh ? NSColor(Accent.hyper) : .labelColor
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [moon, stars]))
        let image = base.withSymbolConfiguration(config) ?? base
        image.isTemplate = false
        return image
    }

    /// The logo in red with a small count badge on its top-right corner,
    /// drawn `offset` points sideways for the shake. The canvas has room on
    /// both sides so the menu bar item keeps its width while it shakes.
    private static func alertImage(badge: Int, offset: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [.systemRed, .systemRed]))
        guard let symbol = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSImage() }
        let text = badge > 9 ? "9+" : "\(badge)"
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let badgeSize = CGSize(width: max(11, textSize.width + 5), height: 11)
        let margin: CGFloat = 3
        let size = CGSize(width: symbol.size.width + badgeSize.width / 2 + margin * 2,
                          height: max(symbol.size.height, 16))

        let image = NSImage(size: size, flipped: false) { _ in
            let origin = CGPoint(x: margin + offset, y: (size.height - symbol.size.height) / 2)
            symbol.draw(in: CGRect(origin: origin, size: symbol.size))
            let badgeRect = CGRect(x: origin.x + symbol.size.width - badgeSize.width / 2,
                                   y: size.height - badgeSize.height,
                                   width: badgeSize.width, height: badgeSize.height)
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: badgeSize.height / 2, yRadius: badgeSize.height / 2).fill()
            (text as NSString).draw(
                at: CGPoint(x: badgeRect.midX - textSize.width / 2, y: badgeRect.midY - textSize.height / 2),
                withAttributes: [.font: font, .foregroundColor: NSColor.white])
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Superkeys: too many windows to arrange"
        return image
    }
}

/// Superkeys was called Hypercaps (bundle id app.hypercaps). Its settings are
/// copied across once, the first time Superkeys runs.
enum LegacySettings {
    private static let oldDomain = "app.hypercaps"
    private static let migratedKey = "migratedFromHypercaps"
    private static let keys = ["bindings.v2", "showCheatSheet", "hasLaunchedBefore"]

    static func migrate() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let old = UserDefaults(suiteName: oldDomain) else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let launchedKey = "hasLaunchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacySettings.migrate()
        let defaults = UserDefaults.standard
        let firstLaunch = !defaults.bool(forKey: Self.launchedKey)
        defaults.set(true, forKey: Self.launchedKey)

        #if DEBUG
        // Lets screenshots show a held key without sending any keystrokes:
        // post space.superkeys.debug.hold with object "hyper", "meh" or "none".
        DistributedNotificationCenter.default().addObserver(
            forName: .init("space.superkeys.debug.hold"), object: nil, queue: .main
        ) { note in
            let layer = note.object as? String
            MainActor.assumeIsolated {
                HyperIndicator.shared.held = layer == "hyper"
                HyperIndicator.shared.meh = layer == "meh"
                switch layer {
                case "hyper": CheatSheet.shared.pressed(.hyper)
                case "meh": CheatSheet.shared.pressed(.meh)
                default: CheatSheet.shared.dismiss()
                }
            }
        }
        // post space.superkeys.debug.window with "arrange", "left", "right", "up" or "down".
        DistributedNotificationCenter.default().addObserver(
            forName: .init("space.superkeys.debug.window"), object: nil, queue: .main
        ) { note in
            let action = note.object as? String
            MainActor.assumeIsolated {
                switch action {
                case "arrange": WindowArranger.shared.arrange()
                case "left": WindowArranger.shared.swap(.left)
                case "right": WindowArranger.shared.swap(.right)
                case "up": WindowArranger.shared.swap(.up)
                case "down": WindowArranger.shared.swap(.down)
                case "snap-left": WindowManager.shared.snap(.left)
                case "snap-right": WindowManager.shared.snap(.right)
                case "fill": WindowManager.shared.snap(.full)
                case "throw-left": WindowManager.shared.throwWindow(.left)
                case "throw-right": WindowManager.shared.throwWindow(.right)
                case "flip": SpaceManager.shared.flipToPreviousDesktop()
                case let desk? where desk.hasPrefix("desktop-"):
                    if let n = Int(desk.dropFirst(8)) { SpaceManager.shared.switchTo(space: n) }
                case let move? where move.hasPrefix("move-"):
                    if let n = Int(move.dropFirst(5)) { SpaceManager.shared.moveFocusedWindow(toSpace: n) }
                case "displays":
                    for d in SpaceManager.shared.displays() {
                        Logger.debugHook.info("display \(d.uuid, privacy: .public) spaces=\(d.spaces.count) current=\(String(describing: d.current), privacy: .public)")
                    }
                default: break
                }
                Logger.debugHook.info("\(action ?? "", privacy: .public): \(AppState.shared.lastAction, privacy: .public)")
            }
        }
        #endif

        Task { @MainActor in
            AppState.shared.bootstrap()
            // Once set up, e.g. launched at login, it stays in the menu bar.
            if firstLaunch || !Permissions.isTrusted {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in SettingsWindowController.shared.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HyperEventTap.shared.stop()
    }
}

#if DEBUG
extension Logger {
    static let debugHook = Logger(subsystem: "space.superkeys", category: "debug")
}
#endif
