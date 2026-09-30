import AppKit
import Carbon.HIToolbox
import CoreGraphics
import os

/// In a password field (or a terminal with Secure Keyboard Entry on) macOS
/// turns on Secure Input, which hides every key press from event taps: ✦ V
/// would reach the app as a plain "v". Hot keys still arrive then, but only
/// ones with ⌘, ⌃ or ⌥ in them.
///
/// So while Secure Input is on, Caps Lock becomes right Control. ✦ V is then
/// really ⌃ V, which types nothing, and a keystroke bound as ✦ V → ⌃ V works
/// on its own. Every other ✦ chord is a ⌃ hot key that runs through the tap's
/// handler as usual. When Secure Input ends, Caps Lock goes back to F18.
///
/// Secure Input has no notification, so it's checked when focus can change:
/// a click, Tab, another app coming forward, and ✦ arriving as a hot key
/// (F18 is registered as one; the tap swallows it first, so it only fires
/// while the tap can't see).
enum SecureInputFallback {
    private static let signature: OSType = 0x534B_4559 // "SKEY"

    /// Caps Lock is right Control right now.
    private(set) static var active = false

    private static var handler: EventHandlerRef?
    private static var hyperKey: EventHotKeyRef?
    private static var chordKeys: [EventHotKeyRef] = []
    private static var activation: NSObjectProtocol?
    private static var pendingCheck: DispatchWorkItem?

    static func start() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        guard InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            SecureInputFallback.received(event)
        }, types.count, &types, nil, &handler) == noErr else { return }
        hyperKey = register(UInt32(KeyCodes.hyperF18), modifiers: 0)
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in SecureInputFallback.checkSoon() }
        check()
    }

    static func stop() {
        pendingCheck?.cancel()
        pendingCheck = nil
        leave()
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        if let hyperKey { UnregisterEventHotKey(hyperKey) }
        hyperKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    /// Focus settles a moment after a click or Tab.
    static func checkSoon() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { check() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    static func check() {
        guard handler != nil else { return }
        let secure = IsSecureEventInputEnabled()
        if secure && !active { enter() } else if !secure && active { leave() }
    }

    private static func enter() {
        active = true
        HIDRemap.capsLockAsControl(true)
        chordKeys = HyperEventTap.shared.chordKeyCodes().compactMap { register(UInt32($0), modifiers: UInt32(controlKey)) }
        Logger.secureInput.info("Secure Input on: ✦ is right Control, \(chordKeys.count) chords as hot keys")
    }

    private static func leave() {
        guard active else { return }
        active = false
        chordKeys.forEach { UnregisterEventHotKey($0) }
        chordKeys = []
        HIDRemap.capsLockAsControl(false)
        Logger.secureInput.info("Secure Input off: ✦ is F18 again")
    }

    private static func register(_ code: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: code)
        guard RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        return ref
    }

    private static func received(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
              id.signature == signature else { return OSStatus(eventNotHandledErr) }
        let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        let code = Int64(id.id)

        if code == KeyCodes.hyperF18 {
            // ✦ the tap didn't see: Secure Input came on without a click or
            // Tab (a page that focuses its password field, say).
            if pressed { check() }
        } else if pressed {
            // ✦ (right Control) with this key: the same as the tap's ✦ chord.
            feed(KeyCodes.hyperF18, down: true)
            feed(code, down: true)
        } else {
            feed(code, down: false)
            feed(KeyCodes.hyperF18, down: false)
        }
        return noErr
    }

    private static func feed(_ code: Int64, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        // A new event copies the modifiers macOS thinks are down, right
        // Control among them.
        event.flags = []
        _ = HyperEventTap.shared.handle(type: down ? .keyDown : .keyUp, event: event)
    }
}

extension Logger {
    static let secureInput = Logger(subsystem: "space.superkeys", category: "secure-input")
}
