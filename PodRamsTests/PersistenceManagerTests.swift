import XCTest
@testable import PodRams

final class PersistenceManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PersistenceManager.clearAll()
    }

    func testSaveAndLoadFavorites() async {
        let (p1, p2) = await makePodcasts([
            ("P1", "https://feed1"),
            ("P2", "https://feed2")
        ])
        await MainActor.run {
            PersistenceManager.saveFavorites([p1, p2])
        }
        let loaded = await PersistenceManager.loadFavorites()
        let loadedTitles = await MainActor.run { loaded.map { $0.title } }
        let loadedFeeds = await MainActor.run { loaded.map { $0.feedUrl ?? "" } }
        XCTAssertEqual(loadedTitles, ["P1", "P2"] )
        XCTAssertEqual(loadedFeeds, ["https://feed1", "https://feed2"])
    }

    func testSaveAndLoadSubscriptions() async {
        let (p1, p2) = await makePodcasts([
            ("P1", "https://feed1"),
            ("P2", "https://feed2")
        ])
        await MainActor.run {
            PersistenceManager.saveSubscriptions([p1, p2])
        }
        let loadedAsync = await PersistenceManager.loadSubscriptions()
        let asyncFeeds = await MainActor.run { loadedAsync.map { $0.feedUrl ?? "" } }
        XCTAssertEqual(asyncFeeds, ["https://feed1", "https://feed2"])
        let loadedSync = await MainActor.run { PersistenceManager.loadSubscriptionsSync() }
        let syncFeeds = await MainActor.run { loadedSync.map { $0.feedUrl ?? "" } }
        XCTAssertEqual(syncFeeds, ["https://feed1", "https://feed2"])
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

    func testLoadPodcastByFeedUrl() async {
        let p = await makePodcast(title: "P1", feedUrl: "https://feed1")
        await MainActor.run {
            PersistenceManager.saveSubscriptions([p])
        }
        PersistenceManager.waitForPersistenceQueue()
        let loaded = await MainActor.run {
            PersistenceManager.loadPodcast(feedUrl: "https://feed1")
        }
        XCTAssertNotNil(loaded)
        let title = await MainActor.run { loaded?.title }
        XCTAssertEqual(title, "P1")
    }

    func testHasData() async {
        PersistenceManager.clearAll()
        XCTAssertFalse(PersistenceManager.hasData)
        let p = await makePodcast(title: "P1", feedUrl: "https://feed1")
        await MainActor.run {
            PersistenceManager.saveFavorites([p])
        }
        PersistenceManager.waitForPersistenceQueue()
        XCTAssertTrue(PersistenceManager.hasData)
    }

    func testPlaybackProgressPersistence() {
        let episode = PodcastEpisode(
            title: "Progress",
            url: URL(string: "https://example.com/progress.mp3")!,
            artworkURL: nil,
            duration: 300,
            showNotes: nil,
            feedUrl: "https://feed"
        )

        PersistenceManager.updatePlaybackProgress(for: episode, position: 123, duration: 300)
        PersistenceManager.waitForPersistenceQueue()

        let stored = PersistenceManager.playbackProgress(for: episode)
        XCTAssertEqual(stored?.position, 123)
        XCTAssertEqual(stored?.duration, 300)

        PersistenceManager.clearPlaybackProgress(for: episode)
        PersistenceManager.waitForPersistenceQueue()

        let cleared = PersistenceManager.playbackProgress(for: episode)
        XCTAssertNil(cleared)
    }
}

private func makePodcasts(_ items: [(String, String)]) async -> (Podcast, Podcast) {
    await MainActor.run {
        (Podcast(title: items[0].0, feedUrl: items[0].1),
         Podcast(title: items[1].0, feedUrl: items[1].1))
    }
}

private func makePodcast(title: String, feedUrl: String) async -> Podcast {
    await MainActor.run { Podcast(title: title, feedUrl: feedUrl) }
}
