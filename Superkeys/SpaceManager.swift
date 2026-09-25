import AppKit
import CoreGraphics

/// Each display has its own desktops ("Displays have separate Spaces", the
/// macOS default). Desktop n means the nth desktop of one display: the one
/// under the pointer when switching, the window's own when moving a window.
/// Positions come from SkyLight's managed display spaces (type 0 entries), in
/// the order SkyLight lists displays.
@MainActor
final class SpaceManager {
    static let shared = SpaceManager()

    /// One display's desktops, in order, and the one it is showing.
    struct Display {
        let uuid: String
        let spaces: [UInt64]
        let current: UInt64?
    }

    /// How macOS's "Switch to Desktop n" shortcuts count desktops when there
    /// is more than one display: across all displays in order (global), or
    /// separately on each (perDisplay). Global is the documented behaviour;
    /// `defaults write space.superkeys desktopNumbering perDisplay` flips it
    /// if a Mac turns out to count per display.
    enum Numbering: String { case global, perDisplay }
    static var numbering: Numbering {
        Numbering(rawValue: UserDefaults.standard.string(forKey: "desktopNumbering") ?? "") ?? .global
    }

    func switchTo(space n: Int) {
        guard n >= 1, n <= 10 else { return }
        guard let display = displayUnderPointer() else { return }
        if spaceID(at: n, on: display) != nil {
            performSwitch(to: n, on: display)
            return
        }
        guard !creating else { return }
        creating = true
        AppState.shared.lastAction = "Creating Desktop \(n)"
        Task {
            defer { creating = false }
            if await createSpaces(upTo: n, on: display) {
                performSwitch(to: n, on: display)
            } else {
                AppState.shared.lastAction = "No Desktop \(n)"
            }
        }
    }

    /// CGSManagedDisplaySetCurrentSpace only updates SkyLight's bookkeeping —
    /// the WindowServer keeps displaying the old Space — so the system shortcut
    /// is the only switch that actually works without disabling SIP.
    private func performSwitch(to n: Int, on display: String) {
        guard let shortcut = shortcut(forDesktop: n, on: display) else {
            AppState.shared.lastAction = "No Desktop \(n)"
            return
        }
        HyperEventTap.shared.post(key: shortcut.keyCode, flags: shortcut.flags)
        AppState.shared.lastAction = "Desktop \(n)"
    }

    /// The system shortcut that shows desktop n of this display.
    private func shortcut(forDesktop n: Int, on display: String) -> MissionControlShortcuts.Shortcut? {
        guard let index = systemIndex(of: n, on: display) else { return nil }
        if MissionControlShortcuts.shortcut(forDesktop: index) == nil {
            MissionControlShortcuts.enable(upTo: index)
        }
        return MissionControlShortcuts.shortcut(forDesktop: index)
    }

    /// Desktop n of a display as macOS's shortcuts number it.
    private func systemIndex(of n: Int, on display: String) -> Int? {
        let all = displays()
        guard let position = all.firstIndex(where: { $0.uuid == display }),
              n >= 1, n <= all[position].spaces.count else { return nil }
        guard Self.numbering == .global else { return n }
        return all[..<position].reduce(0) { $0 + $1.spaces.count } + n
    }

    private var creating = false

    func moveFocusedWindow(toSpace n: Int) {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return
        }
        guard let window = AXWindow.focused() else {
            AppState.shared.lastAction = "No window focused"
            return
        }
        guard let frame = window.cocoaFrame, let screen = AXWindow.screen(for: frame),
              let display = displayUUID(of: screen) else { return }
        let wid = window.windowID
        guard wid != 0, n >= 1, n <= 10 else {
            AppState.shared.lastAction = "No Desktop \(n)"
            return
        }
        guard !creating else { return }

        creating = true
        Task {
            defer { creating = false }
            if spaceID(at: n, on: display) == nil {
                AppState.shared.lastAction = "Creating Desktop \(n)"
                guard await createSpaces(upTo: n, on: display) else {
                    AppState.shared.lastAction = "No Desktop \(n)"
                    return
                }
            }
            guard let target = spaceID(at: n, on: display) else {
                AppState.shared.lastAction = "No Desktop \(n)"
                return
            }
            guard await moveWindow(window, id: wid, to: target, number: n, on: display) else {
                AppState.shared.lastAction = "Couldn't move to Desktop \(n)"
                return
            }
            AppState.shared.lastAction = "Moved to Desktop \(n)"
        }
    }

    private func windowSpaces(_ wid: UInt32) -> [UInt64] {
        guard let connection = SkyLightBridge.mainConnectionID,
              let copy = SkyLightBridge.copySpacesForWindows,
              let list = copy(connection(), 7, [NSNumber(value: wid)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return list.map { $0.uint64Value }
    }

    /// Current macOS ignores the direct move from other processes. Once that
    /// has been observed it is skipped, saving the wait on every later move.
    private var directMoveIgnored = false

    private func moveWindow(_ window: AXWindow, id wid: UInt32, to target: UInt64, number n: Int, on display: String) async -> Bool {
        if !directMoveIgnored, let connection = SkyLightBridge.mainConnectionID,
           let move = SkyLightBridge.moveWindowsToManagedSpace {
            move(connection(), [NSNumber(value: wid)] as CFArray, target)
            try? await Task.sleep(nanoseconds: 150_000_000)
            if windowSpaces(wid).contains(target) {
                performSwitch(to: n, on: display)
                return true
            }
            directMoveIgnored = true
        }
        return await carry(window, id: wid, to: target, desktop: n, on: display)
    }

    /// Holds the window by its title bar and lets macOS carry it through its
    /// own desktop switch. The window changes desktop within a few frames of
    /// the shortcut, so it is released as soon as that registers.
    private func carry(_ window: AXWindow, id wid: UInt32, to target: UInt64, desktop n: Int, on display: String) async -> Bool {
        guard let shortcut = shortcut(forDesktop: n, on: display),
              let original = window.cocoaFrame else { return false }
        let frame = AXWindow.cocoaToAX(original)
        let grab = CGPoint(x: frame.midX, y: frame.minY + 12)
        let pointer = CGEvent(source: nil)?.location ?? grab
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }

        post(.mouseMoved, grab)
        try? await Task.sleep(nanoseconds: 50_000_000)
        post(.leftMouseDown, grab)
        try? await Task.sleep(nanoseconds: 50_000_000)
        var held = grab
        for step in 1...3 {
            held = CGPoint(x: grab.x + CGFloat(step * 5), y: grab.y + CGFloat(step * 2))
            post(.leftMouseDragged, held)
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        HyperEventTap.shared.post(key: shortcut.keyCode, flags: shortcut.flags)

        var moved = false
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if windowSpaces(wid).contains(target) {
                moved = true
                break
            }
        }
        post(.leftMouseUp, held)
        post(.mouseMoved, pointer)
        // The drag nudged the window a few points; put it back.
        window.setCocoaFrame(original)
        return moved
    }

    // MARK: Creating spaces

    /// Presses Mission Control's new-space button until Space n exists.
    ///
    /// Mission Control's accessibility tree moved out of the Dock and into
    /// WindowManager, where the button is identified as mc.spaces.add. Synthetic
    /// clicks are unreliable inside Mission Control, so it is pressed directly.
    /// Mission Control has to be on screen for the tree to exist at all, and it
    /// is opened once for the whole run rather than per space.
    private func createSpaces(upTo n: Int, on display: String) async -> Bool {
        if spaceID(at: n, on: display) != nil { return true }

        let missionControl = MissionControlShortcuts.missionControl
        HyperEventTap.shared.post(key: missionControl.keyCode, flags: missionControl.flags)

        var created = true
        var attempts = 0
        while spaceID(at: n, on: display) == nil {
            attempts += 1
            guard attempts <= 12, let button = await addSpaceButton(on: display),
                  AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                created = false
                break
            }
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if spaceID(at: n, on: display) != nil { break }
            }
        }

        HyperEventTap.shared.post(key: KeyCodes.escape, flags: [])
        try? await Task.sleep(nanoseconds: 350_000_000)
        return created
    }

    /// Mission Control shows one add button per display; pick the one on
    /// this display's screen.
    private func addSpaceButton(on display: String) async -> AXUIElement? {
        guard let windowManager = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.WindowManager").first else { return nil }
        let app = AXUIElementCreateApplication(windowManager.processIdentifier)
        let area = screen(for: display).map { AXWindow.cocoaToAX($0.frame) }
        for _ in 0..<20 {
            var buttons: [AXUIElement] = []
            elements(app, identifier: "mc.spaces.add", depth: 0, into: &buttons)
            if let area, let onScreen = buttons.first(where: { position(of: $0).map(area.contains) ?? false }) {
                return onScreen
            }
            if let first = buttons.first { return first }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private func elements(_ root: AXUIElement, identifier: String, depth: Int, into found: inout [AXUIElement]) {
        if depth > 10 { return }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, "AXIdentifier" as CFString, &value) == .success,
           (value as? String) == identifier {
            found.append(root)
            return
        }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &raw) == .success,
              let children = raw as? [AXUIElement] else { return }
        for child in children {
            elements(child, identifier: identifier, depth: depth + 1, into: &found)
        }
    }

    private func position(of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    /// Every display's desktops, in the order SkyLight lists them. When
    /// "Displays have separate Spaces" is off there is a single entry for all.
    func displays() -> [Display] {
        guard let connection = SkyLightBridge.mainConnectionID,
              let copy = SkyLightBridge.copyManagedDisplaySpaces,
              let raw = copy(connection())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let uuid = entry["Display Identifier"] as? String,
                  let spaces = entry["Spaces"] as? [[String: Any]] else { return nil }
            let current = (entry["Current Space"] as? [String: Any]).flatMap(identifier(of:))
            return Display(uuid: uuid,
                           spaces: spaces.filter { ($0["type"] as? Int ?? 0) == 0 }.compactMap(identifier(of:)),
                           current: current)
        }
    }

    private func spaces(on display: String) -> [UInt64] {
        displays().first { $0.uuid == display }?.spaces ?? []
    }

    private func identifier(of space: [String: Any]) -> UInt64? {
        if let id = space["ManagedSpaceID"] as? UInt64 { return id }
        if let id = space["ManagedSpaceID"] as? Int { return UInt64(id) }
        if let id = space["id64"] as? UInt64 { return id }
        if let id = space["id64"] as? Int { return UInt64(id) }
        return nil
    }

    // MARK: Back and forth

    /// Per display: the desktop it shows now and the one before.
    private var currentSpace: [String: UInt64] = [:]
    private var previousSpace: [String: UInt64] = [:]
    private var spaceObserver: NSObjectProtocol?

    /// Follows every desktop change, including swipes and Control-arrows, so
    /// flipping back works however you got here.
    func trackDesktops() {
        for display in displays() { currentSpace[display.uuid] = display.current }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SpaceManager.shared.activeSpaceChanged() }
        }
    }

    private func activeSpaceChanged() {
        // Full-screen apps and Mission Control aren't desktops (type 0), so
        // they never become a place to flip back to.
        for display in displays() {
            guard let now = display.current, display.spaces.contains(now),
                  now != currentSpace[display.uuid] else { continue }
            if let before = currentSpace[display.uuid] { previousSpace[display.uuid] = before }
            currentSpace[display.uuid] = now
        }
    }

    /// Flips the display under the pointer back to its previous desktop.
    func flipToPreviousDesktop() {
        guard let display = displayUnderPointer(),
              let previous = previousSpace[display],
              let index = spaces(on: display).firstIndex(of: previous) else {
            AppState.shared.lastAction = "No previous desktop"
            return
        }
        performSwitch(to: index + 1, on: display)
    }

    /// What the chord panel shows: each display's desktop count and current
    /// one, with the display's name when there's more than one.
    struct Summary {
        let name: String?
        let count: Int
        let current: Int?
        let underPointer: Bool
    }

    func desktopSummaries() -> [Summary] {
        let all = displays()
        let pointer = displayUnderPointer()
        return all.map { display in
            Summary(name: all.count > 1 ? screen(for: display.uuid)?.localizedName : nil,
                    count: display.spaces.count,
                    current: display.current.flatMap { display.spaces.firstIndex(of: $0) }.map { $0 + 1 },
                    underPointer: display.uuid == pointer)
        }
    }

    private func spaceID(at n: Int, on display: String) -> UInt64? {
        let ids = spaces(on: display)
        guard n >= 1, n <= ids.count else { return nil }
        return ids[n - 1]
    }

    // MARK: Displays

    /// The display whose desktops ☾ acts on: the one under the pointer, so an
    /// empty display (no window to focus) can still be switched.
    private func displayUnderPointer() -> String? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return screen.flatMap(displayUUID(of:))
    }

    /// SkyLight's identifier for a screen's desktops. With "Displays have
    /// separate Spaces" off every screen shares SkyLight's single entry.
    func displayUUID(of screen: NSScreen) -> String? {
        let all = displays()
        if all.count == 1 { return all[0].uuid }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return all.first { $0.uuid.caseInsensitiveCompare(text) == .orderedSame }?.uuid ?? text
    }

    private func screen(for display: String) -> NSScreen? {
        let all = displays()
        if all.count == 1 { return NSScreen.main }
        return NSScreen.screens.first { displayUUID(of: $0) == display }
    }

    /// True when "Displays have separate Spaces" is on, which per-display
    /// desktops need. macOS stores the opposite, as spans-displays.
    static var displaysHaveSeparateSpaces: Bool {
        let spans = CFPreferencesCopyAppValue("spans-displays" as CFString, "com.apple.spaces" as CFString)
        return !((spans as? Bool) ?? ((spans as? Int) == 1))
    }
}

/// The system "Switch to Desktop n" shortcuts.
///
/// macOS ignores CGSMoveWindowsToManagedSpace and CGSAddWindowsToSpaces from
/// another process, so the only way to move a window between Spaces is to hold
/// it with the mouse and let the system carry it during its own Space switch.
/// That switch has to come from these shortcuts, which ship disabled.
enum MissionControlShortcuts {
    struct Shortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString

    /// Symbolic hotkey 118 is Desktop 1, so desktop n is 117 + n; 32 is Mission Control.
    private static func identifier(for desktop: Int) -> Int { 117 + desktop }
    private static let missionControlID = 32

    /// Mission Control is bound to an arrow key, which carries the function
    /// modifier, so the stored flags must be posted verbatim rather than
    /// assuming Control alone.
    static var missionControl: Shortcut {
        shortcut(id: missionControlID, in: current())
            ?? Shortcut(keyCode: 126, flags: [.maskControl, .maskSecondaryFn])
    }

    static var allEnabled: Bool {
        let all = current()
        return (1...9).allSatisfy { isEnabled(entry(id: identifier(for: $0), in: all)) }
    }

    /// Honours a custom binding; Cocoa and CGEventFlags share modifier values.
    static func shortcut(forDesktop desktop: Int) -> Shortcut? {
        let all = current()
        guard isEnabled(entry(id: identifier(for: desktop), in: all)) else { return nil }
        return shortcut(id: identifier(for: desktop), in: all)
            ?? (desktop <= 9 ? KeyCodes.keyCodeForDigit[desktop].map { Shortcut(keyCode: $0, flags: .maskControl) } : nil)
    }

    private static func shortcut(id: Int, in all: [String: Any]?) -> Shortcut? {
        guard let entry = entry(id: id, in: all), isEnabled(entry),
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let code = parameters[1] as? Int, let modifiers = parameters[2] as? Int else { return nil }
        return Shortcut(keyCode: CGKeyCode(code), flags: CGEventFlags(rawValue: UInt64(modifiers)))
    }

    private static func isEnabled(_ entry: [String: Any]?) -> Bool {
        guard let entry else { return false }
        if let flag = entry["enabled"] as? Bool { return flag }
        return (entry["enabled"] as? Int) == 1
    }

    /// Turns on Desktop 1–9 (Control+digit) and, when a second display
    /// numbers its desktops past 9, Desktop 10–16 (Control+Option+Shift+1–7,
    /// out of the way of anything else).
    @discardableResult
    static func enable(upTo last: Int = 9) -> Bool {
        var all = current() ?? [:]
        var changed = false
        for desktop in 1...max(9, min(last, 16)) where !isEnabled(entry(id: identifier(for: desktop), in: all)) {
            let digit = desktop <= 9 ? desktop : desktop - 9
            guard let keyCode = KeyCodes.keyCodeForDigit[digit] else { continue }
            let flags: CGEventFlags = desktop <= 9 ? .maskControl : [.maskControl, .maskAlternate, .maskShift]
            var entry = all[String(identifier(for: desktop))] as? [String: Any] ?? [:]
            entry["enabled"] = true
            if entry["value"] == nil {
                entry["value"] = [
                    "parameters": [65535, Int(keyCode), Int(flags.rawValue)],
                    "type": "standard"
                ]
            }
            all[String(identifier(for: desktop))] = entry
            changed = true
        }
        guard changed else { return true }
        CFPreferencesSetValue(key, all as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(domain)
        return activate()
    }

    private static func current() -> [String: Any]? {
        CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
    }

    private static func entry(id: Int, in all: [String: Any]?) -> [String: Any]? {
        all?[String(id)] as? [String: Any]
    }

    /// Reloads the shortcut table so the change takes effect without a logout.
    private static func activate() -> Bool {
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-u"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
