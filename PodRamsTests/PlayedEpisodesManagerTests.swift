import XCTest
@testable import PodRams

final class PlayedEpisodesManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "playedEpisodes")
        do {
            try withManager { manager in
                manager.playedEpisodes = []
            }
        } catch {
            XCTFail("Failed to reset PlayedEpisodesManager: \(error)")
        }
    }

    func testMarkAsPlayedAndHasBeenPlayed() {
        let e = PodcastEpisode(
            title: "E",
            url: URL(string: "https://ex.com/e.mp3")!,
            artworkURL: nil,
            duration: nil,
            showNotes: nil
        )
        XCTAssertNoThrow(try withManager { manager in
            XCTAssertFalse(manager.hasBeenPlayed(e))
            manager.markAsPlayed(e)
            XCTAssertTrue(manager.hasBeenPlayed(e))
        })
    }

    func testLoadPlayedEpisodesFromUserDefaults() {
        let ids: Set<String> = ["id1", "id2"]
        let data = try! JSONEncoder().encode(ids)
        UserDefaults.standard.set(data, forKey: "playedEpisodes")
        XCTAssertNoThrow(try withManager { manager in
            manager.loadPlayedEpisodes()
            XCTAssertEqual(manager.playedEpisodes, ids)
        })
    }

    private func withManager<R: Sendable>(_ body: @MainActor (PlayedEpisodesManager) throws -> R) throws -> R {
        try MainActor.assumeIsolated {
            try body(PlayedEpisodesManager.shared)
        }
    }
}
