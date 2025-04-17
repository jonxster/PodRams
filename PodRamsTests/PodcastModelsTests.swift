import XCTest
@testable import PodRams

final class PodcastModelsTests: XCTestCase {
    func testPodcastEpisodeCoding() throws {
        let episode = PodcastEpisode(
            title: "Title",
            url: URL(string: "https://example.com/ep.mp3")!,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            duration: 123.0,
            showNotes: "Notes",
            feedUrl: "https://example.com/feed",
            podcastName: "Podcast"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(episode)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PodcastEpisode.self, from: data)
        XCTAssertEqual(decoded, episode)
    }

    func testPodcastSearchResponseDecoding() throws {
        let json = """
        {
            "resultCount": 2,
            "results": [
                {
                    "collectionName": "Podcast 1",
                    "feedUrl": "https://example.com/feed1",
                    "artworkUrl600": "https://example.com/art1.jpg"
                },
                {
                    "collectionName": "Podcast 2",
                    "feedUrl": null,
                    "artworkUrl600": null
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let response = try decoder.decode(PodcastSearchResponse.self, from: data)
        XCTAssertEqual(response.resultCount, 2)
        XCTAssertEqual(response.results.count, 2)
        XCTAssertEqual(response.results[0].collectionName, "Podcast 1")
        XCTAssertEqual(response.results[0].feedUrl, "https://example.com/feed1")
        XCTAssertEqual(response.results[0].artworkUrl600, "https://example.com/art1.jpg")
        XCTAssertEqual(response.results[1].collectionName, "Podcast 2")
        XCTAssertNil(response.results[1].feedUrl)
        XCTAssertNil(response.results[1].artworkUrl600)
    }
}