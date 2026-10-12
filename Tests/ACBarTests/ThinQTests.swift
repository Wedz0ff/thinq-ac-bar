import XCTest
@testable import ACBar

final class ThinQTests: XCTestCase {
    func testKeepsOnlyAirConditioners() {
        let found = ThinQ.airConditioners(in: [
            ["deviceId": "a", "deviceInfo": ["deviceType": "DEVICE_AIR_CONDITIONER", "alias": "Bedroom"]],
            ["deviceId": "b", "deviceInfo": ["deviceType": "DEVICE_REFRIGERATOR", "alias": "Fridge"]],
            ["deviceId": "c", "deviceInfo": ["deviceType": "DEVICE_AIR_CONDITIONER"]],
            ["deviceInfo": ["deviceType": "DEVICE_AIR_CONDITIONER", "alias": "No id"]],
        ])
        XCTAssertEqual(found.map(\.id), ["a", "c"])
        XCTAssertEqual(found.map(\.name), ["Bedroom", "c"])
    }

    func testDecodeReturnsResponseOnSuccess() throws {
        let value = try ThinQ.decode(Data(#"{"response":{"ok":true}}"#.utf8), status: 200)
        XCTAssertEqual((value as? [String: Any])?["ok"] as? Bool, true)
    }

    func testDecodeThrowsApiMessage() {
        let body = Data(#"{"error":{"code":"1218","message":"Invalid token"}}"#.utf8)
        XCTAssertThrowsError(try ThinQ.decode(body, status: 401)) {
            XCTAssertEqual($0.localizedDescription, "Invalid token")
        }
    }

    func testDecodeThrowsStatusForNonJsonBody() {
        XCTAssertThrowsError(try ThinQ.decode(Data("Bad Gateway".utf8), status: 502)) {
            XCTAssertEqual($0.localizedDescription, "HTTP 502: Bad Gateway")
        }
    }
}
