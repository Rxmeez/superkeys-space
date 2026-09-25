import XCTest
@testable import Superkeys_Dev

/// "ctrl+c" and friends, as written in config.toml.
final class KeystrokeTests: XCTestCase {
    func testParsesCombinations() {
        let c = Keystroke.parse("ctrl+c")
        XCTAssertEqual(c?.keyCode, 8)
        XCTAssertEqual(c?.modifiers, .control)
        XCTAssertEqual(c?.label, "C")

        let t = Keystroke.parse("cmd + shift + t")
        XCTAssertEqual(t?.keyCode, 17)
        XCTAssertEqual(t?.modifiers, [.command, .shift])

        XCTAssertEqual(Keystroke.parse("option+F5")?.keyCode, 96)
        XCTAssertEqual(Keystroke.parse("escape")?.modifiers, [])
    }

    func testRefusesNonsense() {
        XCTAssertNil(Keystroke.parse("hyper+c"))
        XCTAssertNil(Keystroke.parse("ctrl+"))
        XCTAssertNil(Keystroke.parse("ctrl+nokey"))
    }

    func testWritesInMacOSOrder() {
        let stroke = Keystroke(keyCode: 13, label: "W", sendKeyCode: 17,
                               sendModifiers: [.shift, .command, .control], sendLabel: "T")
        XCTAssertEqual(stroke.sendText, "ctrl+shift+cmd+t")
        XCTAssertEqual(stroke.sendKeys, ["⌃", "⇧", "⌘", "T"])
    }

    func testTerminalSetIsControlCDR() {
        XCTAssertEqual(Keystroke.terminalSet.map(\.stroke.sendText), ["ctrl+c", "ctrl+d", "ctrl+r"])
    }
}
