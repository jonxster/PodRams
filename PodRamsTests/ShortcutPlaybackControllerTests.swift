import XCTest
#if SWIFT_PACKAGE
@testable import PodRamsCore
#else
@testable import PodRams
#endif

@available(macOS 15, *)
final class ShortcutPlaybackControllerTests: XCTestCase {
    func testTogglePausesWhenAlreadyPlaying() async {
        let (controller, audio, persistence) = await makeFixtures()

        await MainActor.run {
            audio.currentEpisode = sampleEpisode(title: "Now Playing")
            audio.isPlaying = true
        }

        let outcome = await controller.togglePlayback()

        let state = await MainActor.run { (audio.isPlaying, audio.pauseCount, persistence.saveCalls.count) }
        XCTAssertEqual(outcome.state, .paused)
        XCTAssertFalse(state.0)
        XCTAssertEqual(state.1, 1)
        XCTAssertEqual(state.2, 0)
    }

    func testToggleReplaysCurrentEpisodeWhenPaused() async {
        let (controller, audio, persistence) = await makeFixtures()

        await MainActor.run {
            audio.currentEpisode = sampleEpisode(title: "Cached Episode")
            audio.isPlaying = false
        }

        let outcome = await controller.togglePlayback()

        let playedTitle = await MainActor.run { audio.playedEpisodes.last?.title }
        let saveCallCount = await MainActor.run { persistence.saveCalls.count }
        let savedEpisodeTitle = await MainActor.run { persistence.saveCalls.first?.episode.title }
        XCTAssertEqual(outcome.state, .playing)
        XCTAssertEqual(playedTitle, "Cached Episode")
        XCTAssertEqual(saveCallCount, 1)
        XCTAssertEqual(savedEpisodeTitle, "Cached Episode")
    }

    func testToggleFallsBackToPersistedEpisode() async {
        let (controller, audio, persistence) = await makeFixtures()
        let persisted = sampleEpisode(title: "Saved Episode", feedUrl: "https://example.com/feed")
        await MainActor.run {
            persistence.lastPlayback = persisted
        }

        let outcome = await controller.togglePlayback()

        let playedTitle = await MainActor.run { audio.playedEpisodes.last?.title }
        let saveCall = await MainActor.run { persistence.saveCalls.first }
        XCTAssertEqual(outcome.state, .playing)
        XCTAssertEqual(playedTitle, "Saved Episode")
        XCTAssertEqual(saveCall?.episode.title, "Saved Episode")
        XCTAssertEqual(saveCall?.feedUrl, persisted.feedUrl)
    }

    func testPlayLastSavedEpisodeWhenMissing() async {
        let (controller, audio, persistence) = await makeFixtures()

        await MainActor.run {
            persistence.lastPlayback = nil
        }

        let outcome = await controller.playLastSavedEpisode()

        let playedCount = await MainActor.run { audio.playedEpisodes.count }
        let savedCount = await MainActor.run { persistence.saveCalls.count }
        XCTAssertEqual(outcome.state, .idle)
        XCTAssertEqual(playedCount, 0)
        XCTAssertEqual(savedCount, 0)
    }

    // MARK: - Helpers

    private func makeFixtures() async -> (ShortcutPlaybackController, MockShortcutAudioController, MockShortcutPersistence) {
        await MainActor.run {
            let persistence = MockShortcutPersistence()
            let audio = MockShortcutAudioController()
            let controller = ShortcutPlaybackController(
                audioController: audio,
                persistence: persistence
            )
            return (controller, audio, persistence)
        }
    }
}

private func sampleEpisode(title: String, feedUrl: String = "https://example.com/feed") -> PodcastEpisode {
    PodcastEpisode(
        title: title,
        url: URL(string: "https://example.com/audio.mp3")!,
        artworkURL: nil,
        duration: 60,
        showNotes: nil,
        feedUrl: feedUrl,
        podcastName: "Test Podcast"
    )
}

@available(macOS 15, *)
@MainActor
final class MockShortcutAudioController: ShortcutAudioControlling, @unchecked Sendable {
    var isPlaying = false
    var currentEpisode: PodcastEpisode?
    var playedEpisodes: [PodcastEpisode] = []
    var pauseCount = 0

    func playEpisode(_ episode: PodcastEpisode) {
        isPlaying = true
        currentEpisode = episode
        playedEpisodes.append(episode)
    }

    func pauseAudio() {
        isPlaying = false
        pauseCount += 1
    }
}

@available(macOS 15, *)
@MainActor
final class MockShortcutPersistence: ShortcutPersisting, @unchecked Sendable {
    var lastPlayback: PodcastEpisode?
    var saveCalls: [(episode: PodcastEpisode, feedUrl: String?)] = []

    func loadLastPlayback() async -> PodcastEpisode? {
        lastPlayback
    }

    func saveLastPlayback(episode: PodcastEpisode, feedUrl: String?) {
        saveCalls.append((episode, feedUrl))
    }
}
