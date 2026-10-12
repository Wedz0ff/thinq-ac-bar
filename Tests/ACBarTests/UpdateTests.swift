import XCTest
@testable import ACBar

final class UpdateTests: XCTestCase {
    private let dmg = "https://github.com/Wedz0ff/thinq-ac-bar/releases/download/v1.0.2/ACBar.dmg"
    private let page = "https://github.com/Wedz0ff/thinq-ac-bar/releases/tag/v1.0.2"

    private func release(tag: String, assets: [String]) -> [String: Any] {
        ["tag_name": tag, "html_url": page, "assets": assets.map { ["browser_download_url": $0] }]
    }

    func testNewerReleaseOffersItsDiskImage() {
        let update = Update(release: release(tag: "v1.0.2", assets: ["https://github.com/x/notes.txt", dmg]), current: "1.0.1")
        XCTAssertEqual(update?.version, "1.0.2")
        XCTAssertEqual(update?.url.absoluteString, dmg)
    }

    func testSameOrOlderReleaseIsNotAnUpdate() {
        XCTAssertNil(Update(release: release(tag: "v1.0.1", assets: [dmg]), current: "1.0.1"))
        XCTAssertNil(Update(release: release(tag: "v1.0.9", assets: [dmg]), current: "1.0.10"))
    }

    func testReleaseWithoutDiskImageLinksToItsPage() {
        XCTAssertEqual(Update(release: release(tag: "v1.0.2", assets: []), current: "1.0.1")?.url.absoluteString, page)
    }

    func testLinkOutsideGitHubIsRejected() {
        XCTAssertNil(Update(release: release(tag: "v1.0.2", assets: ["http://github.com/a.dmg"]), current: "1.0.1"))
        XCTAssertNil(Update(release: release(tag: "v1.0.2", assets: ["https://evil.example/a.dmg"]), current: "1.0.1"))
        XCTAssertNil(Update(release: [:], current: "1.0.1"))
    }
}
