import XCTest
#if SWIFT_PACKAGE
@testable import PodRamsCore
#else
@testable import PodRams
#endif

final class EpisodeTranscriptionManagerTests: XCTestCase {
    func testCachesTranscriptionAndReusesCachedValue() async throws {
        let preparer = MockAudioPreparer()
        let transcriber = MockTranscriber(result: "hello world")
        let cache = InMemoryTranscriptCache()
        let manager = EpisodeTranscriptionManager(
            audioPreparer: preparer,
            transcriber: transcriber,
            cache: cache
        )

        let episode = PodcastEpisode(
            title: "Test Episode",
            url: URL(string: "https://example.com/audio.mp3")!,
            artworkURL: nil,
            duration: 120,
            showNotes: nil,
            feedUrl: "https://example.com/feed.xml"
        )

        let first = try await manager.transcript(for: episode)
        let second = try await manager.transcript(for: episode)

        XCTAssertEqual(first.text, "hello world")
        XCTAssertEqual(first.text, second.text)
        XCTAssertNotNil(cache.cachedTranscript(for: episode.id))
        let transcriberCalls = await transcriber.callCount
        let preparerCalls = await preparer.callCount
        XCTAssertEqual(transcriberCalls, 1)
        XCTAssertEqual(preparerCalls, 1)
    }

    func testConcurrentRequestsShareSingleTranscriptionTask() async throws {
        let preparer = MockAudioPreparer()
        let transcriber = MockTranscriber(result: "shared result", delayNanoseconds: 50_000_000)
        let cache = InMemoryTranscriptCache()
        let manager = EpisodeTranscriptionManager(
            audioPreparer: preparer,
            transcriber: transcriber,
            cache: cache
        )

        let episode = PodcastEpisode(
            title: "Concurrent Episode",
            url: URL(string: "https://example.com/episode.mp3")!,
            artworkURL: nil,
            duration: 180,
            showNotes: nil,
            feedUrl: nil
        )

        async let first = manager.transcript(for: episode)
        async let second = manager.transcript(for: episode)

        let results = try await [first, second]

        XCTAssertEqual(results[0].text, "shared result")
        XCTAssertEqual(results[0].text, results[1].text)
        let transcriberCalls = await transcriber.callCount
        XCTAssertEqual(transcriberCalls, 1)
    }

    func testDiskCacheRoundTrip() throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("TranscriptionTests-\(UUID().uuidString)", isDirectory: true)
        let cache = DiskTranscriptCache(directory: directory)

        let transcript = EpisodeTranscriptionManager.Transcript(
            text: "round trip",
            generatedAt: Date(),
            sourceEpisodeID: "episode-identifier"
        )

        cache.store(transcript, for: transcript.sourceEpisodeID)
        let loaded = cache.cachedTranscript(for: transcript.sourceEpisodeID)
        XCTAssertEqual(loaded?.text, transcript.text)
        XCTAssertEqual(loaded?.sourceEpisodeID, transcript.sourceEpisodeID)

        cache.removeCachedTranscript(for: transcript.sourceEpisodeID)
        XCTAssertNil(cache.cachedTranscript(for: transcript.sourceEpisodeID))

        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Test Doubles

private actor MockAudioPreparer: TranscriptionAudioPreparing {
    private(set) var prepareCallCount = 0
    var preparedAudio = PreparedAudio(
        url: URL(fileURLWithPath: "/tmp/fake-audio.caf"),
        cleanupURLs: [],
        duration: 60
    )

    func prepareAudio(for url: URL, episodeID: String) async throws -> PreparedAudio {
        prepareCallCount += 1
        return preparedAudio
    }

    var callCount: Int {
        prepareCallCount
    }
}

private actor MockTranscriber: EpisodeTranscribing {
    private(set) var transcribeCallCount = 0
    private let result: String
    private let delayNanoseconds: UInt64

    init(result: String, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func transcribe(preparedAudio: PreparedAudio, metadata: EpisodeTranscriptionMetadata) async throws -> String {
        transcribeCallCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return result
    }

    var callCount: Int {
        transcribeCallCount
    }
}

private final class InMemoryTranscriptCache: TranscriptCaching, @unchecked Sendable {
    private var storage: [String: EpisodeTranscriptionManager.Transcript] = [:]

    func cachedTranscript(for episodeID: String) -> EpisodeTranscriptionManager.Transcript? {
        storage[episodeID]
    }

    func store(_ transcript: EpisodeTranscriptionManager.Transcript, for episodeID: String) {
        storage[episodeID] = transcript
    }

    func removeCachedTranscript(for episodeID: String) {
        storage.removeValue(forKey: episodeID)
    }
}
