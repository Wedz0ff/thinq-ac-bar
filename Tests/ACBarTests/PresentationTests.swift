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

    private func ac(_ id: String, on: Bool, target: Double? = 22) -> AC {
        var ac = AC(id: id, name: id, state: [:])
        ac.on = on
        ac.target = target
        return ac
    }

    func testMenuBarShowsTheTargetOfTheOnlyRunningAC() {
        XCTAssertEqual(menuBarText([ac("a", on: false), ac("b", on: true, target: 22.5)]), "\(22.5.formatted())°")
    }

    func testMenuBarCountsSeveralRunningACs() {
        XCTAssertEqual(menuBarText([ac("a", on: true), ac("b", on: true), ac("c", on: false)]), "2")
    }

    func testMenuBarHasNoTextWhenNothingRunsOrTheTargetIsUnknown() {
        XCTAssertNil(menuBarText([]))
        XCTAssertNil(menuBarText([ac("a", on: false)]))
        XCTAssertNil(menuBarText([ac("a", on: true, target: nil)]))
    }
}
