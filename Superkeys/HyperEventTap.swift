import AppKit
import CoreGraphics

// CGEventTapCallBack is a C function pointer: it must be a file-level function
// with unlabeled parameters and no captured context.
private func superkeysTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    HyperEventTap.shared.handle(type: type, event: event)
}

/// Turns Caps Lock into the Hyper Key and right Command into the Meh Key: held
/// modifiers other applications never see. Every key pressed while either is
/// held is consumed, mapped or not.
///
/// Hyper snaps windows and opens apps. Meh switches and moves between desktops.
///
/// The tap callback runs on the main run loop, so this state is only touched
/// from the main thread; UI work still hops through the main actor because
/// Swift cannot see that.
final class HyperEventTap: @unchecked Sendable {
    static let shared = HyperEventTap()

    private static let syntheticMarker: Int64 = 0x4859504552

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// ✦ plus one key, or a key then a second key (a group).
    struct Chord: Hashable {
        let first: Int64
        let second: Int64?
        init(_ first: Int, _ second: Int?) {
            self.first = Int64(first)
            self.second = second.map(Int64.init)
        }
        init(_ first: Int64, _ second: Int64?) {
            self.first = first
            self.second = second
        }
    }

    private var apps: Set<Chord> = []
    /// First keys of groups: pressing one waits for the second key.
    private var groups: Set<Int64> = []
    /// The group waiting for its second key; if ✦ is let go instead, the
    /// first key's own binding runs.
    private var pendingGroup: Int64?
    private var hyperHeld = false
    private var mehHeld = false
    /// Keys whose key-down was consumed; their repeats and key-up are consumed too.
    private var consumed: Set<Int64> = []
    private var posting = false
    /// One source for everything Superkeys sends, rather than one per event
    /// (a held keystroke repeats about 30 times a second).
    private lazy var eventSource = CGEventSource(stateID: .hidSystemState)

    /// ✦ chord → the key combination it sends.
    private var keystrokes: [Chord: (key: CGKeyCode, flags: CGEventFlags)] = [:]
    /// Keys whose ✦ press went out as a keystroke: their repeats and release
    /// go out too, even if ✦ is let go first.
    private var sending: [Int64: (key: CGKeyCode, flags: CGEventFlags)] = [:]

    func setBindings(apps: Set<Chord>, keystrokes map: [Chord: (CGKeyCode, CGEventFlags)]) {
        self.apps = apps
        keystrokes = map.mapValues { (key: $0.0, flags: $0.1) }
        groups = Set(apps.compactMap { $0.second == nil ? nil : $0.first })
            .union(map.keys.compactMap { $0.second == nil ? nil : $0.first })
        pendingGroup = nil
    }

    var isRunning: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        stop()

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        var created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: superkeysTapCallback,
            userInfo: nil
        )
        if created == nil {
            created = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: superkeysTapCallback,
                userInfo: nil
            )
        }
        guard let port = created else { return false }
        HIDRemap.enable()

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        CapsLock.unlock()
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        consumed.removeAll()
        sending.removeAll()
        release()
        releaseMeh()
        HIDRemap.disable()
        CapsLock.unlock()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            release()
            releaseMeh()
            return pass
        }
        if posting || event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return pass
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == KeyCodes.hyperF18 || keyCode == KeyCodes.capsLock {
            handleHyperKey(type: type, keyCode: keyCode, event: event)
            return nil
        }
        if keyCode == KeyCodes.mehF19 {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                if type == .keyDown { pressMeh() } else if type == .keyUp { releaseMeh() }
            }
            return nil
        }

        // ✦ plus a key that sends a keystroke: down, repeats and up all go out
        // as that keystroke, so holding it repeats like the real thing.
        if let sent = sending[keyCode] {
            if type == .keyDown { send(sent, down: true, repeating: true) }
            if type == .keyUp { send(sent, down: false); sending[keyCode] = nil }
            return nil
        }
        if type == .keyDown, hyperHeld, !mehHeld,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty {
            // The second key of a group.
            if let first = pendingGroup {
                pendingGroup = nil
                Task { @MainActor in CheatSheet.shared.dismiss() }
                if keyCode == Int64(KeyCodes.escape) {
                    consumed.insert(keyCode)
                    return nil
                }
                let chord = Chord(first, keyCode)
                if let sent = keystrokes[chord] {
                    sending[keyCode] = sent
                    send(sent, down: true)
                    return nil
                }
                if apps.contains(chord) {
                    consumed.insert(keyCode)
                    open(first, keyCode)
                    return nil
                }
                // Not in the group: carry on as if the group was never started.
            }
            // The first key of a group waits for the second.
            if groups.contains(keyCode) {
                pendingGroup = keyCode
                consumed.insert(keyCode)
                let code = Int(keyCode)
                Task { @MainActor in CheatSheet.shared.showGroup(code) }
                return nil
            }
            if let sent = keystrokes[Chord(keyCode, nil)] {
                sending[keyCode] = sent
                Task { @MainActor in CheatSheet.shared.dismiss() }
                send(sent, down: true)
                return nil
            }
        }

        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return consumed.contains(keyCode) ? nil : pass
            }
            guard hyperHeld || mehHeld else { return pass }
            consumed.insert(keyCode)
            Task { @MainActor in CheatSheet.shared.dismiss() }
            let flags = event.flags
            let shift = flags.contains(.maskShift)
            let control = flags.contains(.maskControl)
            let option = flags.contains(.maskAlternate)
            // Both held at once is left free for a future layer.
            if mehHeld && !hyperHeld {
                dispatchMeh(keyCode, shift: shift, control: control, option: option)
            } else if hyperHeld && !mehHeld {
                dispatchHyper(keyCode, shift: shift, control: control, option: option)
            }
            return nil
        case .keyUp:
            return consumed.remove(keyCode) == nil ? pass : nil
        case .flagsChanged:
            // ☾ with right Option flips to the previous desktop. The modifier
            // itself passes through; it does nothing on its own.
            if mehHeld, keyCode == KeyCodes.rightOption, rightOptionWentDown(event.flags) {
                Task { @MainActor in
                    CheatSheet.shared.dismiss()
                    SpaceManager.shared.flipToPreviousDesktop()
                }
            }
            if event.flags.contains(.maskAlphaShift) {
                CapsLock.unlock()
                event.flags.remove(.maskAlphaShift)
            }
            return pass
        default:
            return pass
        }
    }

    /// Hardware events say which Option key is down; synthetic ones may not, in
    /// which case Option being down at all is the best signal. Releasing right
    /// Option while left Option stays held is not a press.
    private func rightOptionWentDown(_ flags: CGEventFlags) -> Bool {
        if flags.rawValue & KeyCodes.rightOptionFlag != 0 { return true }
        return flags.contains(.maskAlternate) && flags.rawValue & KeyCodes.leftOptionFlag == 0
    }

    private func handleHyperKey(type: CGEventType, keyCode: Int64, event: CGEvent) {
        // Autorepeat arrives every few milliseconds while the key is held.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
        if keyCode == KeyCodes.capsLock { CapsLock.unlock() }
        switch type {
        case .keyDown:
            press()
        case .keyUp:
            finishGroup()
            release()
        case .flagsChanged where keyCode == KeyCodes.capsLock:
            // Without the HID remap Caps Lock only reports flagsChanged.
            if event.flags.contains(.maskAlphaShift) { press() } else { finishGroup(); release() }
        default:
            break
        }
    }

    /// Meh: 1–9 switches desktop, Shift with 1–9 moves the window there.
    private func dispatchMeh(_ keyCode: Int64, shift: Bool, control: Bool, option: Bool) {
        guard let digit = KeyCodes.digitForKeyCode[keyCode], !control, !option else { return }
        let n = KeyCodes.spaceNumber(for: digit)
        if shift {
            Task { @MainActor in SpaceManager.shared.moveFocusedWindow(toSpace: n) }
        } else {
            Task { @MainActor in SpaceManager.shared.switchTo(space: n) }
        }
    }

    /// Hyper: arrows and Return snap the window, assigned keys open apps.
    private func dispatchHyper(_ keyCode: Int64, shift: Bool, control: Bool, option: Bool) {
        guard !control else { return }
        if option {
            // ✦ ⌥ ← / → moves the window to the next display as it is.
            guard !shift else { return }
            switch keyCode {
            case KeyCodes.leftArrow: Task { @MainActor in WindowManager.shared.throwWindow(.left) }
            case KeyCodes.rightArrow: Task { @MainActor in WindowManager.shared.throwWindow(.right) }
            default: break
            }
            return
        }
        if shift {
            // ✦ ⇧ arrow swaps the window with its neighbour in that direction.
            let direction: WindowArranger.Direction
            switch keyCode {
            case KeyCodes.leftArrow: direction = .left
            case KeyCodes.rightArrow: direction = .right
            case KeyCodes.upArrow: direction = .up
            case KeyCodes.downArrow: direction = .down
            default: return
            }
            Task { @MainActor in WindowArranger.shared.swap(direction) }
            return
        }

        switch keyCode {
        case KeyCodes.upArrow:
            Task { @MainActor in WindowArranger.shared.arrange() }
        case KeyCodes.downArrow:
            return
        case KeyCodes.leftArrow:
            Task { @MainActor in
                if OnboardingWindowController.handleHyperArrow(.left) { return }
                WindowManager.shared.snap(.left)
            }
        case KeyCodes.rightArrow:
            Task { @MainActor in
                if OnboardingWindowController.handleHyperArrow(.right) { return }
                WindowManager.shared.snap(.right)
            }
        case KeyCodes.returnKey, KeyCodes.keypadEnter:
            Task { @MainActor in WindowManager.shared.snap(.full) }
        default:
            guard apps.contains(Chord(keyCode, nil)) else { return }
            open(keyCode, nil)
        }
    }

    private func press() {
        guard !hyperHeld else { return }
        hyperHeld = true
        publish(true)
        Task { @MainActor in CheatSheet.shared.pressed(.hyper) }
    }

    /// ✦ let go while a group waited for its second key: run the first key's
    /// own binding, if it has one.
    private func finishGroup() {
        guard let first = pendingGroup else { return }
        pendingGroup = nil
        if let sent = keystrokes[Chord(first, nil)] {
            send(sent, down: true)
            send(sent, down: false)
        } else if apps.contains(Chord(first, nil)) {
            open(first, nil)
        }
    }

    private func release() {
        pendingGroup = nil
        guard hyperHeld else { return }
        hyperHeld = false
        publish(false)
        Task { @MainActor in CheatSheet.shared.dismiss() }
    }

    private func open(_ first: Int64, _ second: Int64?) {
        #if DEBUG
        if captured != nil {
            captured?.append("open \(first)" + (second.map { " then \($0)" } ?? ""))
            return
        }
        #endif
        let (a, b) = (Int(first), second.map(Int.init))
        Task { @MainActor in AppLauncher.launch(keyCode: a, then: b) }
    }

    #if DEBUG
    /// While set, keystrokes and app launches are recorded here instead.
    private var captured: [String]?

    /// Runs made-up key sequences through the handler with ✦ held and
    /// reports what each would do. Nothing is sent or opened.
    func selfTestGroups(first: CGKeyCode, second: CGKeyCode, other: CGKeyCode) -> [String] {
        func feed(_ key: CGKeyCode, _ type: CGEventType) {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type == .keyDown)!
            _ = handle(type: type, event: e)
        }
        func tap(_ key: CGKeyCode) { feed(key, .keyDown); feed(key, .keyUp) }
        func run(_ name: String, _ body: () -> Void) -> String {
            captured = []
            press()
            body()
            let log = "\(name): " + (captured!.isEmpty ? "nothing" : captured!.joined(separator: ", "))
            captured = nil
            return log
        }
        return [
            run("✦ first then second") { tap(first); tap(second); finishGroup(); release() },
            run("✦ first, let go") { tap(first); finishGroup(); release() },
            run("✦ first, esc") { tap(first); tap(CGKeyCode(KeyCodes.escape)); finishGroup(); release() },
            run("✦ first then a key outside the group") { tap(first); tap(other); finishGroup(); release() },
            run("✦ other alone") { tap(other); finishGroup(); release() },
        ]
    }

    /// Feeds made-up key events through the handler with ✦ held and reports
    /// what would have been sent, without sending anything. Returns a log.
    func selfTestKeystrokes(keyCode: CGKeyCode) -> [String] {
        captured = []
        defer { captured = nil }
        func feed(_ type: CGEventType, repeating: Bool = false) -> String {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type == .keyDown)!
            if repeating { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
            return handle(type: type, event: e) == nil ? "consumed" : "passed"
        }
        var log: [String] = []
        press()
        log.append("✦ down, key down: \(feed(.keyDown))")
        log.append("key repeat: \(feed(.keyDown, repeating: true))")
        release()
        log.append("✦ up first, then key up: \(feed(.keyUp))")
        log.append("key down without ✦: \(feed(.keyDown))")
        _ = feed(.keyUp)
        return log + ["sent: " + (captured ?? []).joined(separator: ", ")]
    }
    #endif

    private func send(_ stroke: (key: CGKeyCode, flags: CGEventFlags), down: Bool, repeating: Bool = false) {
        #if DEBUG
        if captured != nil {
            let mods = [(CGEventFlags.maskControl, "ctrl"), (.maskAlternate, "opt"), (.maskShift, "shift"), (.maskCommand, "cmd")]
                .filter { stroke.flags.contains($0.0) }.map(\.1)
            captured?.append((mods + ["key\(stroke.key)"]).joined(separator: "+") + (down ? (repeating ? " repeat" : " down") : " up"))
            return
        }
        #endif
        posting = true
        defer { posting = false }
        guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: stroke.key, keyDown: down) else { return }
        e.flags = stroke.flags
        if repeating { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    func post(key: CGKeyCode, flags: CGEventFlags) {
        posting = true
        defer { posting = false }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            // Delivery can be asynchronous, so also tag events to skip re-entry.
            e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    private func pressMeh() {
        pendingGroup = nil
        guard !mehHeld else { return }
        mehHeld = true
        Task { @MainActor in
            HyperIndicator.shared.meh = true
            CheatSheet.shared.pressed(.meh)
        }
    }

    private func releaseMeh() {
        guard mehHeld else { return }
        mehHeld = false
        Task { @MainActor in
            HyperIndicator.shared.meh = false
            CheatSheet.shared.dismiss()
        }
    }

    private func publish(_ held: Bool) {
        Task { @MainActor in HyperIndicator.shared.held = held }
    }
}
