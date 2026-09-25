import CoreGraphics
import XCTest
@testable import Superkeys_Dev

/// The event tap's decisions for keystrokes and groups, with made-up events:
/// nothing is sent and no app is opened (the self-tests record instead).
final class KeyHandlingTests: XCTestCase {
    private let tap = HyperEventTap.shared
    private let o = 31, p = 35, b = 11, c = 8, k = 40

    override func tearDown() {
        tap.setBindings(apps: [], keystrokes: [:])
    }

    func testKeystrokeRepeatsAndReleases() {
        tap.setBindings(apps: [], keystrokes: [HyperEventTap.Chord(c, nil): (CGKeyCode(c), .maskControl)])
        let log = tap.selfTestKeystrokes(keyCode: CGKeyCode(c))
        XCTAssertEqual(log[0], "✦ down, key down: consumed")
        XCTAssertEqual(log[3], "key down without ✦: passed")
        XCTAssertEqual(log.last, "sent: ctrl+key8 down, ctrl+key8 repeat, ctrl+key8 up")
    }

    func testGroups() {
        tap.setBindings(
            apps: [HyperEventTap.Chord(o, nil), HyperEventTap.Chord(o, p), HyperEventTap.Chord(b, nil)],
            keystrokes: [HyperEventTap.Chord(o, k): (CGKeyCode(k), .maskCommand)])
        let apps = tap.selfTestGroups(first: CGKeyCode(o), second: CGKeyCode(p), other: CGKeyCode(b))
        XCTAssertEqual(apps, [
            "✦ first then second: open 31 then 35",
            "✦ first, let go: open 31",
            "✦ first, esc: nothing",
            "✦ first then a key outside the group: open 11",
            "✦ other alone: open 11",
        ])
        let strokes = tap.selfTestGroups(first: CGKeyCode(o), second: CGKeyCode(k), other: CGKeyCode(b))
        XCTAssertEqual(strokes.first, "✦ first then second: cmd+key40 down, cmd+key40 up")
    }

    func testGroupWithoutItsOwnKeyDoesNothingOnRelease() {
        tap.setBindings(apps: [HyperEventTap.Chord(o, p)], keystrokes: [:])
        let log = tap.selfTestGroups(first: CGKeyCode(o), second: CGKeyCode(p), other: CGKeyCode(b))
        XCTAssertEqual(log[1], "✦ first, let go: nothing")
    }

    @MainActor func testProblemReportFillsInTheForm() throws {
        let url = Feedback.url(.problem)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.path, "/Rxmeez/superkeys-space/issues/new")
        XCTAssertEqual(items.map(\.name), ["template", "version", "macos", "mac", "diagnostics"])
        XCTAssertEqual(items.first?.value, "bug.yml")
        XCTAssertFalse(try XCTUnwrap(items.last?.value).isEmpty)
    }

    @MainActor func testDiagnosticsLeaveOutBindings() {
        let text = Feedback.diagnostics()
        print(text)
        XCTAssertTrue(text.hasPrefix("Superkeys "))
        for app in BindingsStore.shared.bindings {
            XCTAssertFalse(text.contains(app.bundleID), "diagnostics mention \(app.bundleID)")
        }
    }
}
