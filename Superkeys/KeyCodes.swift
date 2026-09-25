import CoreGraphics
import Foundation

enum KeyCodes {
    static let capsLock: Int64 = 57
    /// Caps Lock is remapped to F18 (keycode 79) by HIDRemap while running.
    static let hyperF18: Int64 = 79
    /// Right Command is remapped to F19 (keycode 80) and becomes the Meh Key.
    static let mehF19: Int64 = 80
    static let rightOption: Int64 = 61
    /// Device-dependent flags (NX_DEVICERALTKEYMASK, NX_DEVICELALTKEYMASK) that
    /// tell right Option from left in flagsChanged events.
    static let rightOptionFlag: UInt64 = 0x40
    static let leftOptionFlag: UInt64 = 0x20
    static let escape: CGKeyCode = 53
    static let returnKey: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let leftArrow: Int64 = 123
    static let rightArrow: Int64 = 124
    static let downArrow: Int64 = 125
    static let upArrow: Int64 = 126
    /// ✦ with any of these moves or arranges windows, so they can't open apps.
    static let windowKeys: Set<Int64> = [leftArrow, rightArrow, upArrow, downArrow, returnKey, keypadEnter]

    /// Physical US ANSI number row keycodes mapped to the digit they sit under.
    static let digitForKeyCode: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0
    ]

    /// Keycodes for digits 1...9, used by the Control+number desktop fallback.
    static let keyCodeForDigit: [Int: CGKeyCode] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25
    ]

    private static let named: [Int: String] = [
        48: "Tab", 49: "Space", 51: "Delete", 117: "Del", 115: "Home", 119: "End",
        116: "PgUp", 121: "PgDn", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
        96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16",
        64: "F17", 90: "F20", 36: "Return", 53: "Escape", 123: "Left", 124: "Right", 125: "Down", 126: "Up"
    ]

    /// US ANSI positions for keys people write by hand in a settings file.
    private static let typed: [String: Int] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32,
        "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "[": 33, "]": 30, "\\": 42, "-": 27, "=": 24, "`": 50
    ]

    /// The key code for a key as written in a settings file, e.g. "B" or "F5".
    static func keyCode(forLabel label: String) -> Int? {
        let wanted = label.trimmingCharacters(in: .whitespaces)
        if let code = typed[wanted.uppercased()] { return code }
        return named.first { $0.value.caseInsensitiveCompare(wanted) == .orderedSame }?.key
    }

    /// Display name for a recorded key. Falls back to the typed character.
    static func label(forKeyCode keyCode: Int, characters: String?) -> String {
        if let name = named[keyCode] { return name }
        guard let characters, let first = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(first),
              !("\u{F700}"..."\u{F8FF}").contains(Character(first)) else { return "" }
        return characters.uppercased()
    }

    /// Space number (1-based) for a digit key; 0 means Space 10.
    static func spaceNumber(for digit: Int) -> Int { digit == 0 ? 10 : digit }
}
