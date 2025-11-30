import XCTest
#if SWIFT_PACKAGE
@testable import PodRamsCore
#else
@testable import PodRams
#endif

final class TranscriptionHistoryStoreTests: XCTestCase {
    func testUpsertAndRemovePersistsHistory() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("TranscriptionHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("history.json")
        let store = TranscriptionHistoryStore(fileURL: storeURL)

        let first = TranscriptionHistoryItem(
            episodeID: "episode-1",
            podcastTitle: "Swift over Coffee",
            episodeTitle: "Episode One",
            artworkURL: nil,
            transcriptText: "Hello world",
            generatedAt: Date(),
            feedUrl: "https://example.com/feed"
        )

        let second = TranscriptionHistoryItem(
            episodeID: "episode-2",
            podcastTitle: "Swift over Coffee",
            episodeTitle: "Episode Two",
            artworkURL: nil,
            transcriptText: "Another transcript",
            generatedAt: Date().addingTimeInterval(10),
            feedUrl: "https://example.com/feed"
        )

        let afterFirst = await store.upsert(first)
        XCTAssertEqual(afterFirst.count, 1)
        XCTAssertEqual(afterFirst.first?.episodeID, first.episodeID)

        let afterSecond = await store.upsert(second)
        XCTAssertEqual(afterSecond.count, 2)
        XCTAssertEqual(afterSecond.first?.episodeID, second.episodeID)

        let persistedStore = TranscriptionHistoryStore(fileURL: storeURL)
        let persisted = await persistedStore.loadHistory()
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(persisted.first?.episodeID, second.episodeID)

        let afterRemoval = await store.remove(id: first.episodeID)
        XCTAssertEqual(afterRemoval.count, 1)
        XCTAssertEqual(afterRemoval.first?.episodeID, second.episodeID)

        let removalVerificationStore = TranscriptionHistoryStore(fileURL: storeURL)
        let afterRemovalReload = await removalVerificationStore.loadHistory()
        XCTAssertEqual(afterRemovalReload.count, 1)
        XCTAssertEqual(afterRemovalReload.first?.episodeID, second.episodeID)
    }
}
