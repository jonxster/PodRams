import XCTest
@testable import PodRams

final class HTMLStrippedStringTests: XCTestCase {
    func testHtmlStrippedRemovesTags() {
        let html = "<p>Hello<br>World!</p>"
        let stripped = html.htmlStripped
        XCTAssertTrue(stripped.contains("Hello"))
        XCTAssertTrue(stripped.contains("World"))
        XCTAssertFalse(stripped.contains("<"))
        XCTAssertFalse(stripped.contains(">"))
    }

    func testHtmlStrippedPlainString() {
        let plain = "Just a plain string"
        XCTAssertEqual(plain.htmlStripped, plain)
    }
}