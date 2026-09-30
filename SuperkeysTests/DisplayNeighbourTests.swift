import XCTest
@testable import Superkeys_Dev

/// Which display an arrow reaches, in Cocoa coordinates (up is +y).
@MainActor
final class DisplayNeighbourTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1800, height: 1169)

    func testDisplayAboveIsUp() {
        let above = CGRect(x: -300, y: 1169, width: 2560, height: 1440)
        let displays = [laptop, above]
        XCTAssertEqual(WindowManager.neighbour(of: laptop, among: displays, toward: .up), 1)
        XCTAssertEqual(WindowManager.neighbour(of: above, among: displays, toward: .down), 0)
        XCTAssertNil(WindowManager.neighbour(of: laptop, among: displays, toward: .down))
        XCTAssertNil(WindowManager.neighbour(of: laptop, among: displays, toward: .right))
        XCTAssertNil(WindowManager.neighbour(of: laptop, among: displays, toward: .left))
    }

    func testSideBySideIsLeftAndRight() {
        let right = CGRect(x: 1800, y: -200, width: 2560, height: 1440)
        let displays = [laptop, right]
        XCTAssertEqual(WindowManager.neighbour(of: laptop, among: displays, toward: .right), 1)
        XCTAssertEqual(WindowManager.neighbour(of: right, among: displays, toward: .left), 0)
        XCTAssertNil(WindowManager.neighbour(of: laptop, among: displays, toward: .up))
    }

    func testLinedUpDisplayBeatsADiagonalOne() {
        let above = CGRect(x: 0, y: 1169, width: 1800, height: 1169)
        let diagonal = CGRect(x: 1800, y: 1300, width: 1800, height: 1169)
        XCTAssertEqual(WindowManager.neighbour(of: laptop, among: [laptop, diagonal, above], toward: .up), 2)
    }

    func testSideArrowsReachADisplayAboveOrBelow() {
        let above = CGRect(x: -772, y: 1169, width: 3440, height: 1440)
        let displays = [laptop, above]
        XCTAssertEqual(WindowManager.display(beside: laptop, among: displays, toward: .right), 1)
        XCTAssertEqual(WindowManager.display(beside: laptop, among: displays, toward: .left), 1)
        XCTAssertEqual(WindowManager.display(beside: above, among: displays, toward: .right), 0)
    }

    func testSideArrowsPreferADisplayToTheSide() {
        let right = CGRect(x: 1800, y: 0, width: 1800, height: 1169)
        let above = CGRect(x: 0, y: 1169, width: 1800, height: 1169)
        let displays = [laptop, right, above]
        XCTAssertEqual(WindowManager.display(beside: laptop, among: displays, toward: .right), 1)
        XCTAssertEqual(WindowManager.display(beside: laptop, among: displays, toward: .left), 2)
    }

    func testLastInARowStopsAtTheEdge() {
        let middle = CGRect(x: 1800, y: 0, width: 1800, height: 1169)
        let last = CGRect(x: 3600, y: 0, width: 1800, height: 1169)
        XCTAssertNil(WindowManager.display(beside: last, among: [laptop, middle, last], toward: .right))
    }
}

/// When a snapped window counts as already on its half.
@MainActor
final class SnappedFrameTests: XCTestCase {
    private let half = CGRect(x: 952, y: 46, width: 1708, height: 1394)

    func testTerminalRoundedToWholeRowsIsStillThere() {
        // Ghostty keeps the top left corner and grows to a whole row.
        let ghostty = CGRect(x: 952, y: 30, width: 1708, height: 1410)
        XCTAssertTrue(WindowManager.close(ghostty, half))
    }

    func testWindowElsewhereIsNot() {
        XCTAssertFalse(WindowManager.close(CGRect(x: 200, y: 300, width: 800, height: 600), half))
        XCTAssertFalse(WindowManager.close(half.offsetBy(dx: 0, dy: -40), half))
    }
}

/// What's New shows the release's notes page as the app reads it.
@MainActor
final class WhatsNewTests: XCTestCase {
    func testNotesKeepTheirSymbols() {
        for html in ["<li>✦ ← / →</li>", "<li>&#x2726; &#x2190; / &#x2192;</li>"] {
            let text = WhatsNew.attributed(html.data(using: .utf8)!)?.string ?? ""
            XCTAssertTrue(text.contains("✦ ← / →"), text)
        }
    }
}
