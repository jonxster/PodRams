import XCTest
#if SWIFT_PACKAGE
@testable import PodRamsCore
#else
@testable import PodRams
#endif

final class RSSParserTests: XCTestCase {
    func testParseSimpleRSSFeed() {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
            <channel>
                <title>Test Channel</title>
                <itunes:image href="https://example.com/art.jpg"/>
                <item>
                    <title>Episode A</title>
                    <enclosure url="https://example.com/a.mp3" length="1000" type="audio/mpeg"/>
                    <itunes:duration>10:00</itunes:duration>
                    <description>Desc A</description>
                </item>
            </channel>
        </rss>
        """
        let data = Data(rss.utf8)
        let parser = RSSParser(feedUrl: "https://feed")
        let (episodes, artwork, channelTitle) = parser.parse(data: data)
        XCTAssertEqual(channelTitle, "Test Channel")
        XCTAssertEqual(artwork?.absoluteString, "https://example.com/art.jpg")
        XCTAssertEqual(episodes.count, 1)
        let ep = episodes[0]
        XCTAssertEqual(ep.title, "Episode A")
        XCTAssertEqual(ep.url.absoluteString, "https://example.com/a.mp3")
        XCTAssertNotNil(ep.duration)
        XCTAssertTrue(ep.duration! >= 0)
        XCTAssertEqual(ep.showNotes, "Desc A")
    }
}
