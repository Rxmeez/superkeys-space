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
    private var appKeyCodes: Set<Int64> = []
    private var hyperHeld = false
    private var mehHeld = false
    /// Keys whose key-down was consumed; their repeats and key-up are consumed too.
    private var consumed: Set<Int64> = []
    private var posting = false

    func setAppKeyCodes(_ codes: Set<Int64>) {
        appKeyCodes = codes
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
            release()
        case .flagsChanged where keyCode == KeyCodes.capsLock:
            // Without the HID remap Caps Lock only reports flagsChanged.
            if event.flags.contains(.maskAlphaShift) { press() } else { release() }
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
            guard appKeyCodes.contains(keyCode) else { return }
            let code = Int(keyCode)
            Task { @MainActor in AppLauncher.launch(keyCode: code) }
        }
    }

    private func press() {
        guard !hyperHeld else { return }
        hyperHeld = true
        publish(true)
        Task { @MainActor in CheatSheet.shared.pressed(.hyper) }
    }

    private func release() {
        guard hyperHeld else { return }
        hyperHeld = false
        publish(false)
        Task { @MainActor in CheatSheet.shared.dismiss() }
    }

    func post(key: CGKeyCode, flags: CGEventFlags) {
        posting = true
        defer { posting = false }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            // Delivery can be asynchronous, so also tag events to skip re-entry.
            e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    private func pressMeh() {
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
