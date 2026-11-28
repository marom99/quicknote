import AppKit
import XCTest
@testable import freewrite

final class DestinationMenuLabelTests: XCTestCase {
    func testShortNameIsShownInFull() {
        XCTAssertEqual(DestinationMenuLabel.shortened("Quick Note", toFit: 150), "Quick Note")
    }

    func testLongNameIsEllipsizedToItsWidthBudget() {
        let name = "Project Archive Journal Notes"
        let shortened = DestinationMenuLabel.shortened(name, toFit: 150)

        XCTAssertTrue(shortened.hasSuffix("…"))
        XCTAssertLessThan(shortened.count, name.count)
        XCTAssertLessThanOrEqual(width(of: shortened), 150 + 0.5)
        XCTAssertTrue(name.hasPrefix(shortened.dropLast()), "The shortened name should keep the start of the destination name")
    }

    func testShorterBudgetStillKeepsAnEllipsis() {
        let shortened = DestinationMenuLabel.shortened("Quick Note", toFit: 40)

        XCTAssertTrue(shortened.hasSuffix("…"))
        XCTAssertLessThanOrEqual(width(of: shortened), 40 + 0.5)
    }

    private func width(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: DestinationMenuLabel.fontSize)]).width
    }
}
