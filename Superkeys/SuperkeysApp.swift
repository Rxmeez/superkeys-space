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
        if hyper.needsAttention && !hyper.held && !hyper.meh {
            return Self.attentionImage()
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

    /// The usual logo with a small orange dot: the keys should be on but
    /// aren't. Drawn at display time so the logo follows the menu bar's
    /// light or dark appearance.
    private static func attentionImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSImage() }
        let dot: CGFloat = 6
        let size = CGSize(width: symbol.size.width + 2, height: max(symbol.size.height, 16))
        let image = NSImage(size: size, flipped: false) { _ in
            let origin = CGPoint(x: 0, y: (size.height - symbol.size.height) / 2)
            let tinted = symbol.copy() as! NSImage
            tinted.lockFocus()
            NSColor.labelColor.set()
            CGRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: CGRect(origin: origin, size: symbol.size))
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: CGRect(x: size.width - dot, y: 0.5, width: dot, height: dot)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Superkeys: needs attention"
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

/// Superkeys and Superkeys Dev (a development build) both remap Caps Lock and
/// right ⌘, so only one should run. On launch, if the other is running, ask
/// which to keep.
enum OtherCopy {
    private static let identifiers = ["space.superkeys", "space.superkeys.dev"]

    /// Returns false when this copy should quit.
    @MainActor
    static func resolve() -> Bool {
        let mine = Bundle.main.bundleIdentifier ?? ""
        let others = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return identifiers.contains(id) && $0 != .current
        }
        guard let other = others.first else { return true }
        let otherName = other.localizedName ?? "Superkeys"
        let myName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Superkeys"
        guard other.bundleIdentifier != mine else {
            // A second copy of the same app: the first one keeps running.
            other.activate()
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(otherName) is already running"
        alert.informativeText = "\(otherName) and \(myName) both use Caps Lock and right ⌘, so only one can run at a time."
        alert.addButton(withTitle: "Quit \(otherName)")
        alert.addButton(withTitle: "Keep \(otherName)")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        other.terminate()
        // Give it a moment to hand the keys back before this copy takes them.
        let deadline = Date().addingTimeInterval(3)
        while !other.isTerminated, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if !other.isTerminated { other.forceTerminate() }
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let launchedKey = "hasLaunchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app: leave the keys, windows and
        // settings alone, and don't offer to quit another copy.
        if TestRun.active { return }
        guard OtherCopy.resolve() else {
            NSApp.terminate(nil)
            return
        }
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
                case "snap-left": if !OnboardingWindowController.handleHyperArrow(.left) { WindowManager.shared.snap(.left) }
                case "snap-right": if !OnboardingWindowController.handleHyperArrow(.right) { WindowManager.shared.snap(.right) }
                case "fill": WindowManager.shared.snap(.full)
                case "whatsnew": WhatsNew.show()
                case "settings": SettingsWindowController.shared.show()
                case "settings-advanced":
                    SettingsWindowController.shared.show()
                    SettingsWindowController.shared.select(.advanced)
                case let s? where s.hasPrefix("group-"):
                    if let code = Int(s.dropFirst(6)) { CheatSheet.shared.showGroup(code) }
                case let s? where s.hasPrefix("selftest-groups-"):
                    let codes = s.dropFirst("selftest-groups-".count).split(separator: "-").compactMap { CGKeyCode($0) }
                    let log = HyperEventTap.shared.selfTestGroups(first: codes[0], second: codes[1], other: codes[2])
                    try? log.joined(separator: "\n").write(toFile: NSTemporaryDirectory() + "superkeys-selftest.txt",
                                                           atomically: true, encoding: .utf8)
                case let s? where s.hasPrefix("selftest-keystroke-"):
                    let code = CGKeyCode(s.dropFirst("selftest-keystroke-".count)) ?? 8
                    let log = HyperEventTap.shared.selfTestKeystrokes(keyCode: code).joined(separator: "\n")
                    try? log.write(toFile: NSTemporaryDirectory() + "superkeys-selftest.txt", atomically: true, encoding: .utf8)
                case "untrusted": AppState.shared.debugUntrusted = true
                case "trusted": AppState.shared.debugUntrusted = false
                case "appearance-light": NSApp.appearance = NSAppearance(named: .aqua)
                case "appearance-dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                case "appearance-system": NSApp.appearance = nil
                case let s? where s.hasPrefix("onboarding"):
                    OnboardingWindowController.debugShow(step: Int(s.dropFirst("onboarding-".count)) ?? 0)
                case "attention-on": HyperIndicator.shared.needsAttention = true
                case "attention-off": HyperIndicator.shared.needsAttention = false
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
            OnboardingWindowController.noteLaunch(firstLaunch: firstLaunch)
            // New users get the tour; after that, Settings only opens itself
            // when access is missing. Launched at login it stays quiet.
            if !OnboardingWindowController.hasCompleted {
                OnboardingWindowController.show()
            } else if !Permissions.isTrusted {
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
