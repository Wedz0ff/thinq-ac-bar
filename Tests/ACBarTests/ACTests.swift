import XCTest
@testable import ACBar

final class ACTests: XCTestCase {
    private func state(_ json: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    func testParsesThinQState() throws {
        let ac = AC(id: "1", name: "Room", state: try state("""
        {"airConJobMode":{"currentJobMode":"AIR_DRY"},"powerSave":{"powerSaveEnabled":true},
         "temperature":{"currentTemperature":23.5,"targetTemperature":22,"unit":"C"},
         "airFlow":{"windStrength":"HIGH"},"windDirection":{"rotateUpDown":true},
         "operation":{"airConOperationMode":"POWER_ON"}}
        """))

        XCTAssertTrue(ac.on)
        XCTAssertEqual(ac.current, 23.5)
        XCTAssertEqual(ac.target, 22)
        XCTAssertEqual(ac.mode, "AIR_DRY")
        XCTAssertEqual(ac.fan, "HIGH")
        XCTAssertTrue(ac.swing)
        XCTAssertTrue(ac.powerSave)
    }

    func testMissingStateFallsBackToOff() {
        let ac = AC(id: "1", name: "Room", state: [:])
        XCTAssertFalse(ac.on)
        XCTAssertNil(ac.target)
        XCTAssertEqual(ac.mode, "COOL")
        XCTAssertEqual(ac.fan, "AUTO")
    }

    func testKeepsHalfDegreeTarget() throws {
        let ac = AC(id: "1", name: "Room", state: try state(#"{"temperature":{"targetTemperature":22.5}}"#))
        XCTAssertEqual(ac.target, 22.5)
    }
}
