import XCTest
@testable import Superkeys_Dev

/// Settings lists: groups kept together, second keys under the first.
final class KeyGroupsTests: XCTestCase {
    private func app(_ label: String, _ code: Int, then label2: String? = nil, _ code2: Int? = nil) -> BoundApp {
        BoundApp(keyCode: code, label: label, bundleID: "x.\(label)\(label2 ?? "")", name: label,
                 keyCode2: code2, label2: label2)
    }

    private func describe(_ rows: [KeyGroups.Row<BoundApp>]) -> [String] {
        rows.map {
            switch $0.kind {
            case .header(let label): return "header \(label)"
            case .item(let app, let indented): return (indented ? "  " : "") + KeySequence.text(app.label, app.label2)
            }
        }
    }

    func testGroupsSitUnderTheirFirstKey() {
        let items = [app("T", 17), app("O", 31, then: "P", 35), app("B", 11), app("O", 31), app("O", 31, then: "M", 46)]
        let rows = KeyGroups.rows(items, first: \.keyCode, label: \.label, second: \.keyCode2, label2: \.label2)
        XCTAssertEqual(describe(rows), ["B", "O", "  O then M", "  O then P", "T"])
    }

    func testGroupWithoutItsOwnKeyGetsAHeader() {
        let items = [app("G", 5, then: "C", 8)]
        let rows = KeyGroups.rows(items, first: \.keyCode, label: \.label, second: \.keyCode2, label2: \.label2)
        XCTAssertEqual(describe(rows), ["header G", "  G then C"])
    }
}
