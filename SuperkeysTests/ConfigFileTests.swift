import XCTest
@testable import Superkeys_Dev

/// config.toml: what's read, what's refused, and that writing reads back.
final class ConfigFileTests: XCTestCase {
    func testReadsAppsKeystrokesAndGroups() {
        let reading = ConfigFile.read("""
        show_chords_while_held = false
        desktop_numbering = "per-display"

        [apps]
        B = "app.zen-browser.zen"  # Zen
        O = "md.obsidian"
        "O P" = "com.1password.1password"

        [keys]
        C = "ctrl+c"
        "O K" = "cmd+shift+k"
        """)
        XCTAssertFalse(reading.syntaxError)
        XCTAssertEqual(reading.problems, [])
        let config = reading.config
        XCTAssertFalse(config.showChordsWhileHeld)
        XCTAssertEqual(config.desktopNumbering, .perDisplay)
        XCTAssertEqual(config.apps.map { KeySequence.text($0.label, $0.label2) }, ["B", "O", "O then P"])
        XCTAssertEqual(config.apps[2].keyCode, 31)
        XCTAssertEqual(config.apps[2].keyCode2, 35)
        XCTAssertEqual(config.keystrokes.count, 2)
        XCTAssertEqual(config.keystrokes[0].sendModifiers, .control)
        XCTAssertEqual(config.keystrokes[1].keyCode2, 40)
        XCTAssertEqual(config.keystrokes[1].sendModifiers, [.command, .shift])
    }

    func testWritingReadsBackTheSame() {
        let original = ConfigFile.read("""
        [apps]
        B = "app.zen-browser.zen"
        "G C" = "com.apple.calculator"
        ";" = "com.apple.Safari"
        [keys]
        R = "ctrl+r"
        "O K" = "cmd+k"
        """).config
        let again = ConfigFile.read(original.text())
        XCTAssertFalse(again.syntaxError)
        XCTAssertEqual(again.problems, [])
        XCTAssertEqual(again.config.apps.map(\.id), original.apps.map(\.id))
        XCTAssertEqual(again.config.apps.map(\.bundleID), original.apps.map(\.bundleID))
        XCTAssertEqual(again.config.keystrokes.map(\.id), original.keystrokes.map(\.id))
        XCTAssertEqual(again.config.keystrokes.map(\.sendText), ["ctrl+r", "cmd+k"])
    }

    func testSyntaxErrorAppliesNothing() {
        let reading = ConfigFile.read("""
        [apps]
        B = "app.zen-browser.zen"
        this line is broken
        """)
        XCTAssertTrue(reading.syntaxError)
        XCTAssertEqual(reading.problems.first?.line, 3)
    }

    func testBadEntriesAreSkippedWithAReason() {
        let reading = ConfigFile.read("""
        [apps]
        B = "app.zen-browser.zen"
        B = "com.apple.Safari"
        "G G" = "com.apple.calculator"
        "O P Q" = "com.apple.Notes"
        Up = "com.apple.Notes"
        C = "ctrl+c"
        [keys]
        X = "hyper+x"
        """)
        XCTAssertFalse(reading.syntaxError)
        XCTAssertEqual(reading.config.apps.map(\.label), ["B"])
        let lines = reading.problems.map(\.line)
        XCTAssertEqual(lines, [3, 4, 5, 6, 7, 9])
        XCTAssertTrue(reading.problems[0].message.contains("twice"))
        XCTAssertTrue(reading.problems[1].message.contains("different"))
        XCTAssertTrue(reading.problems[2].message.contains("two keys at most"))
        XCTAssertTrue(reading.problems[3].message.contains("moves windows"))
        XCTAssertTrue(reading.problems[4].message.contains("[keys]"))
    }

    @MainActor
    func testOlderFilesGainAKeysSectionOnce() {
        let old = "[apps]\nB = \"app.zen-browser.zen\"\n"
        let upgraded = ConfigSync.addingKeysSection(to: old)
        XCTAssertTrue(upgraded.hasPrefix(old))
        XCTAssertTrue(upgraded.contains("\n[keys]\n"))
        XCTAssertEqual(ConfigSync.addingKeysSection(to: upgraded), upgraded)
        // A file mid-edit with a syntax error is left alone.
        let broken = "[apps]\noops\n"
        XCTAssertEqual(ConfigSync.addingKeysSection(to: broken), broken)
    }
}
