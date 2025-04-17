import XCTest
@testable import PodRams

final class PlayedEpisodesManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "playedEpisodes")
        PlayedEpisodesManager.shared.playedEpisodes = []
    }

    func testMarkAsPlayedAndHasBeenPlayed() {
        let e = PodcastEpisode(
            title: "E",
            url: URL(string: "https://ex.com/e.mp3")!,
            artworkURL: nil,
            duration: nil,
            showNotes: nil
        )
        XCTAssertFalse(PlayedEpisodesManager.shared.hasBeenPlayed(e))
        PlayedEpisodesManager.shared.markAsPlayed(e)
        XCTAssertTrue(PlayedEpisodesManager.shared.hasBeenPlayed(e))
    }

    func testLoadPlayedEpisodesFromUserDefaults() {
        let ids: Set<String> = ["id1", "id2"]
        let data = try! JSONEncoder().encode(ids)
        UserDefaults.standard.set(data, forKey: "playedEpisodes")
        PlayedEpisodesManager.shared.loadPlayedEpisodes()
        XCTAssertEqual(PlayedEpisodesManager.shared.playedEpisodes, ids)
    }
}