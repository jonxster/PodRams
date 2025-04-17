import XCTest
@testable import PodRams

final class PersistenceManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PersistenceManager.clearAll()
    }

    func testSaveAndLoadFavorites() async {
        let p1 = Podcast(title: "P1", feedUrl: "https://feed1")
        let p2 = Podcast(title: "P2", feedUrl: "https://feed2")
        PersistenceManager.saveFavorites([p1, p2])
        let loaded = await PersistenceManager.loadFavorites()
        XCTAssertEqual(loaded.map { $0.title }, ["P1", "P2"] )
        XCTAssertEqual(loaded.map { $0.feedUrl }, ["https://feed1", "https://feed2"])
    }

    func testSaveAndLoadSubscriptions() async {
        let p1 = Podcast(title: "P1", feedUrl: "https://feed1")
        let p2 = Podcast(title: "P2", feedUrl: "https://feed2")
        PersistenceManager.saveSubscriptions([p1, p2])
        let loadedAsync = await PersistenceManager.loadSubscriptions()
        XCTAssertEqual(loadedAsync.map { $0.feedUrl }, ["https://feed1", "https://feed2"])
        let loadedSync = PersistenceManager.loadSubscriptionsSync()
        XCTAssertEqual(loadedSync.map { $0.feedUrl }, ["https://feed1", "https://feed2"])
    }

    func testSaveAndLoadCue() async {
        let e1 = PodcastEpisode(
            title: "E1",
            url: URL(string: "https://ex.com/e1.mp3")!,
            artworkURL: nil,
            duration: nil,
            showNotes: nil
        )
        let e2 = PodcastEpisode(
            title: "E2",
            url: URL(string: "https://ex.com/e2.mp3")!,
            artworkURL: nil,
            duration: nil,
            showNotes: nil
        )
        PersistenceManager.saveCue([e1, e2], feedUrl: "https://feed")
        let loaded = await PersistenceManager.loadCue()
        XCTAssertEqual(loaded, [e1, e2])
    }

    func testSaveAndLoadLastPlayback() async {
        let e = PodcastEpisode(
            title: "Last",
            url: URL(string: "https://ex.com/last.mp3")!,
            artworkURL: nil,
            duration: 10,
            showNotes: nil
        )
        PersistenceManager.saveLastPlayback(episode: e, feedUrl: "https://feed")
        let loaded = await PersistenceManager.loadLastPlayback()
        XCTAssertEqual(loaded, e)
    }

    func testLoadPodcastByFeedUrl() {
        let p = Podcast(title: "P1", feedUrl: "https://feed1")
        PersistenceManager.saveSubscriptions([p])
        let loaded = PersistenceManager.loadPodcast(feedUrl: "https://feed1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "P1")
    }

    func testHasData() async {
        PersistenceManager.clearAll()
        XCTAssertFalse(PersistenceManager.hasData)
        let p = Podcast(title: "P1", feedUrl: "https://feed1")
        PersistenceManager.saveFavorites([p])
        XCTAssertTrue(PersistenceManager.hasData)
    }
}