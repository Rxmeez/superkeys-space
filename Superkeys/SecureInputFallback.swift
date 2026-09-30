import Carbon.HIToolbox
import CoreGraphics
import os

/// In a password field (or a terminal with Secure Keyboard Entry on) macOS
/// turns on Secure Input, which hides every key press from event taps: ✦ V
/// would reach the app as a plain "v". Hot keys still arrive then, so ✦ and ☾
/// (F18 and F19 after the remap) are also registered as hot keys.
///
/// The tap sees keys before hot keys do and swallows ✦ and ☾, so these only
/// fire while the tap can't see. Then, for as long as ✦ or ☾ is held, every
/// other key is a hot key too, and each press and release goes through the
/// tap's own handler, so chords do exactly what they always do.
enum SecureInputFallback {
    private static let signature: OSType = 0x534B_4559 // "SKEY"
    private static let shiftBit: UInt32 = 0x100

    private static var handler: EventHandlerRef?
    private static var layerKeys: [EventHotKeyRef] = []
    private static var chordKeys: [EventHotKeyRef] = []
    /// ✦ and ☾, whichever are held.
    private static var held: Set<Int64> = []
    /// Chord keys pressed and not yet released, with their modifiers.
    private static var down: [Int64: CGEventFlags] = [:]

    /// Every key but the modifiers, Caps Lock, fn and ✦ / ☾ themselves.
    private static let chordCodes: [UInt32] = (0...126).map(UInt32.init).filter {
        !(54...63).contains($0) && $0 != UInt32(KeyCodes.hyperF18) && $0 != UInt32(KeyCodes.mehF19)
    }

    static func start() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        guard InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            SecureInputFallback.received(event)
        }, types.count, &types, nil, &handler) == noErr else { return }
        layerKeys = [KeyCodes.hyperF18, KeyCodes.mehF19].compactMap { register(UInt32($0), modifiers: 0) }
        if layerKeys.count < 2 { Logger.secureInput.error("✦ / ☾ hot keys taken; they won't work in password fields") }
    }

    static func stop() {
        endChord()
        layerKeys.forEach { UnregisterEventHotKey($0) }
        layerKeys = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private static func register(_ code: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: code | (modifiers == 0 ? 0 : shiftBit))
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
        let code = Int64(id.id & ~shiftBit)
        let flags: CGEventFlags = id.id & shiftBit == 0 ? [] : .maskShift

        if code == KeyCodes.hyperF18 || code == KeyCodes.mehF19 {
            if pressed {
                guard held.insert(code).inserted else { return noErr }
                Logger.secureInput.info("Secure Input: \(code == KeyCodes.hyperF18 ? "✦" : "☾", privacy: .public) held as a hot key")
                if chordKeys.isEmpty {
                    chordKeys = chordCodes.flatMap { code in
                        [register(code, modifiers: 0), register(code, modifiers: UInt32(shiftKey))].compactMap { $0 }
                    }
                }
                feed(code, down: true)
            } else {
                guard held.remove(code) != nil else { return noErr }
                feed(code, down: false)
                if held.isEmpty { endChord() }
            }
        } else if pressed {
            down[code] = flags
            feed(code, down: true, flags: flags)
        } else if let flags = down.removeValue(forKey: code) {
            feed(code, down: false, flags: flags)
        }
        return noErr
    }

    /// Lets go of any chord key still down, so nothing is left sending, then
    /// frees the keys for typing again.
    private static func endChord() {
        for (code, flags) in down { feed(code, down: false, flags: flags) }
        down = [:]
        held = []
        chordKeys.forEach { UnregisterEventHotKey($0) }
        chordKeys = []
    }

    private static func feed(_ code: Int64, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        // A new event copies the modifiers macOS thinks are down; use only
        // the ones the hot key was registered with.
        event.flags = flags
        _ = HyperEventTap.shared.handle(type: down ? .keyDown : .keyUp, event: event)
    }
}

extension Logger {
    static let secureInput = Logger(subsystem: "space.superkeys", category: "secure-input")
}
