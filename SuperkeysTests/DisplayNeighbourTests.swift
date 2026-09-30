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
}
