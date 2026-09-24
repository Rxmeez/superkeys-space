import AppKit
import CoreGraphics

/// Space indexes are 1-based positions in the display's user-space list
/// (type 0 entries of SkyLight's managed display spaces). This can differ from
/// Mission Control's visual order if the two ever diverge.
@MainActor
final class SpaceManager {
    static let shared = SpaceManager()


    func switchTo(space n: Int) {
        guard n >= 1, n <= 10 else { return }
        if spaceID(at: n) != nil {
            performSwitch(to: n)
            return
        }
        guard !creating else { return }
        creating = true
        AppState.shared.lastAction = "Creating Desktop \(n)"
        Task {
            defer { creating = false }
            if await createSpaces(upTo: n) {
                performSwitch(to: n)
            } else {
                AppState.shared.lastAction = "No Desktop \(n)"
            }
        }
    }

    /// CGSManagedDisplaySetCurrentSpace only updates SkyLight's bookkeeping —
    /// the WindowServer keeps displaying the old Space — so the system shortcut
    /// is the only switch that actually works without disabling SIP.
    private func performSwitch(to n: Int) {
        if MissionControlShortcuts.shortcut(forDesktop: n) == nil {
            MissionControlShortcuts.enable()
        }
        guard let shortcut = MissionControlShortcuts.shortcut(forDesktop: n) else {
            AppState.shared.lastAction = "No Desktop \(n)"
            return
        }
        HyperEventTap.shared.post(key: shortcut.keyCode, flags: shortcut.flags)
        AppState.shared.lastAction = "Desktop \(n)"
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
        let wid = window.windowID
        guard wid != 0, n >= 1, n <= 10 else {
            AppState.shared.lastAction = "No Desktop \(n)"
            return
        }
        guard !creating else { return }

        creating = true
        Task {
            defer { creating = false }
            if spaceID(at: n) == nil {
                AppState.shared.lastAction = "Creating Desktop \(n)"
                guard await createSpaces(upTo: n) else {
                    AppState.shared.lastAction = "No Desktop \(n)"
                    return
                }
            }
            guard let target = spaceID(at: n) else {
                AppState.shared.lastAction = "No Desktop \(n)"
                return
            }
            guard await moveWindow(window, id: wid, to: target, number: n) else {
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

    private func moveWindow(_ window: AXWindow, id wid: UInt32, to target: UInt64, number n: Int) async -> Bool {
        if !directMoveIgnored, let connection = SkyLightBridge.mainConnectionID,
           let move = SkyLightBridge.moveWindowsToManagedSpace {
            move(connection(), [NSNumber(value: wid)] as CFArray, target)
            try? await Task.sleep(nanoseconds: 150_000_000)
            if windowSpaces(wid).contains(target) {
                performSwitch(to: n)
                return true
            }
            directMoveIgnored = true
        }
        return await carry(window, id: wid, to: target, desktop: n)
    }

    /// Holds the window by its title bar and lets macOS carry it through its
    /// own desktop switch. The window changes desktop within a few frames of
    /// the shortcut, so it is released as soon as that registers.
    private func carry(_ window: AXWindow, id wid: UInt32, to target: UInt64, desktop n: Int) async -> Bool {
        if MissionControlShortcuts.shortcut(forDesktop: n) == nil { MissionControlShortcuts.enable() }
        guard let shortcut = MissionControlShortcuts.shortcut(forDesktop: n),
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
    private func createSpaces(upTo n: Int) async -> Bool {
        if spaceID(at: n) != nil { return true }

        let missionControl = MissionControlShortcuts.missionControl
        HyperEventTap.shared.post(key: missionControl.keyCode, flags: missionControl.flags)

        var created = true
        var attempts = 0
        while spaceID(at: n) == nil {
            attempts += 1
            guard attempts <= 12, let button = await addSpaceButton(),
                  AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                created = false
                break
            }
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if spaceID(at: n) != nil { break }
            }
        }

        HyperEventTap.shared.post(key: KeyCodes.escape, flags: [])
        try? await Task.sleep(nanoseconds: 350_000_000)
        return created
    }

    private func addSpaceButton() async -> AXUIElement? {
        guard let windowManager = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.WindowManager").first else { return nil }
        let app = AXUIElementCreateApplication(windowManager.processIdentifier)
        for _ in 0..<20 {
            if let button = element(app, identifier: "mc.spaces.add", depth: 0) { return button }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private func element(_ root: AXUIElement, identifier: String, depth: Int) -> AXUIElement? {
        if depth > 10 { return nil }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, "AXIdentifier" as CFString, &value) == .success,
           (value as? String) == identifier {
            return root
        }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &raw) == .success,
              let children = raw as? [AXUIElement] else { return nil }
        for child in children {
            if let found = element(child, identifier: identifier, depth: depth + 1) { return found }
        }
        return nil
    }

    private func userSpaceIDs() -> [UInt64] {
        guard let connection = SkyLightBridge.mainConnectionID,
              let copy = SkyLightBridge.copyManagedDisplaySpaces,
              let display = mainDisplayUUID(),
              let raw = copy(connection())?.takeRetainedValue() as? [[String: Any]],
              let entry = raw.first(where: { ($0["Display Identifier"] as? String) == display }),
              let spaces = entry["Spaces"] as? [[String: Any]] else { return [] }
        return spaces.filter { ($0["type"] as? Int ?? 0) == 0 }.compactMap(identifier(of:))
    }

    private func identifier(of space: [String: Any]) -> UInt64? {
        if let id = space["ManagedSpaceID"] as? UInt64 { return id }
        if let id = space["ManagedSpaceID"] as? Int { return UInt64(id) }
        if let id = space["id64"] as? UInt64 { return id }
        if let id = space["id64"] as? Int { return UInt64(id) }
        return nil
    }

    // MARK: Back and forth

    private var currentSpace: UInt64?
    private var previousSpace: UInt64?
    private var spaceObserver: NSObjectProtocol?

    /// Follows every desktop change, including swipes and Control-arrows, so
    /// flipping back works however you got here.
    func trackDesktops() {
        currentSpace = activeSpaceID()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SpaceManager.shared.activeSpaceChanged() }
        }
    }

    private func activeSpaceChanged() {
        // Full-screen apps and Mission Control are not desktops to return to.
        guard let now = activeSpaceID(), now != currentSpace, userSpaceIDs().contains(now) else { return }
        previousSpace = currentSpace
        currentSpace = now
    }

    func flipToPreviousDesktop() {
        guard let previous = previousSpace,
              let index = userSpaceIDs().firstIndex(of: previous) else {
            AppState.shared.lastAction = "No previous desktop"
            return
        }
        performSwitch(to: index + 1)
    }

    private func activeSpaceID() -> UInt64? {
        guard let connection = SkyLightBridge.mainConnectionID else { return nil }
        return SkyLightBridge.getActiveSpace?(connection())
    }

    /// How many desktops the main display has and which one is showing. The
    /// active space is trustworthy because every switch goes through macOS.
    func desktopSummary() -> (count: Int, current: Int?) {
        let ids = userSpaceIDs()
        guard let active = activeSpaceID() else { return (ids.count, nil) }
        return (ids.count, ids.firstIndex(of: active).map { $0 + 1 })
    }

    private func spaceID(at n: Int) -> UInt64? {
        let ids = userSpaceIDs()
        guard n >= 1, n <= ids.count else { return nil }
        return ids[n - 1]
    }

    private func mainDisplayUUID() -> String? {
        let number = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = number.map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
        // In the macOS 14 SDK this returns Unmanaged<CFUUID>?; newer SDKs may
        // return CFUUID? directly. Adjust if the compiler objects.
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
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
            ?? KeyCodes.keyCodeForDigit[desktop].map { Shortcut(keyCode: $0, flags: .maskControl) }
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

    @discardableResult
    static func enable() -> Bool {
        var all = current() ?? [:]
        var changed = false
        for desktop in 1...9 where !isEnabled(entry(id: identifier(for: desktop), in: all)) {
            guard let keyCode = KeyCodes.keyCodeForDigit[desktop] else { continue }
            var entry = all[String(identifier(for: desktop))] as? [String: Any] ?? [:]
            entry["enabled"] = true
            if entry["value"] == nil {
                entry["value"] = [
                    "parameters": [65535, Int(keyCode), Int(CGEventFlags.maskControl.rawValue)],
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
