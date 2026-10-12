import XCTest
@testable import ACBar

final class PresentationTests: XCTestCase {
    func testNextTargetStepsOneDegree() {
        XCTAssertEqual(nextTarget(22, by: 1), 23)
        XCTAssertEqual(nextTarget(22.5, by: -1), 21.5)
    }

    func testNextTargetStopsAtTheRangeLimits() {
        XCTAssertEqual(nextTarget(29.5, by: 1), 30)
        XCTAssertEqual(nextTarget(30, by: 1), 30)
        XCTAssertEqual(nextTarget(18.5, by: -1), 18)
        XCTAssertEqual(nextTarget(16, by: -1), 18)
    }
}
