import SwiftUI
import OSLog

private let debugLogger = AppLogger.debug

/// Provides a set of debug commands accessible via the app's menu.
/// Includes commands to run tests and create test data for rapid testing.
struct DebugCommands: Commands {
    var body: some Commands {
        CommandMenu("Debug") {
            // Runs all tests.
            Button("Run All Tests") {
                AppTests.runAllTests()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Divider()

            testButton("Test Audio Player", key: "1") { try AppTests.testAudioPlayer() }
            testButton("Test Player View",  key: "2") { try AppTests.testPlayerView() }
            testButton("Test Download Manager", key: "3") { try AppTests.testDownloadManager() }
            testButton("Test Podcast Fetcher",  key: "4") { try AppTests.testPodcastFetcher() }

            Divider()

            Button("Create Test Podcast") { createTestPodcast() }
                .keyboardShortcut("p", modifiers: [.command, .option])

            Button("Create Test Episode") { createTestEpisode() }
                .keyboardShortcut("e", modifiers: [.command, .option])
        }
    }
}

private extension DebugCommands {
    @ViewBuilder
    func testButton(_ title: String, key: Character, _ action: @escaping () throws -> Void) -> some View {
        Button(title) { runTest(title, action) }
            .keyboardShortcut(KeyEquivalent(key), modifiers: [.command, .option])
    }

    func runTest(_ name: String, _ block: () throws -> Void) {
        do { try block() }
        catch {
            let errorDescription = String(describing: error)
            debugLogger.error("❌ \(name, privacy: .public) failed: \(errorDescription, privacy: .public)")
        }
    }
}

private extension Notification.Name {
    static let addTestPodcast = Notification.Name("AddTestPodcast")
    static let addTestEpisode = Notification.Name("AddTestEpisode")
}

private extension DebugCommands {
    /// Creates a test podcast populated with sample episodes and posts a notification.
    @MainActor
    func createTestPodcast() {
        let feed = "https://example.com/feed"
        let artBase = "https://example.com"

        let testPodcast = Podcast(
            title: "Test Podcast",
            feedUrl: feed,
            episodes: []
        )
        testPodcast.feedArtworkURL = URL(string: "\(artBase)/image.jpg")

        for i in 1...5 {
            guard
                let audioURL = URL(string: "\(artBase)/episode\(i).mp3")
            else {
                debugLogger.error("❌ Invalid episode URL for index \(i, privacy: .public)")
                return
            }

            let episode = PodcastEpisode(
                title: "Test Episode \(i)",
                url: audioURL,
                artworkURL: URL(string: "\(artBase)/image\(i).jpg"),
                duration: Double(i * 300),
                showNotes: "This is test episode \(i)",
                feedUrl: feed,
                podcastName: "Test Podcast"
            )
            testPodcast.episodes.append(episode)
        }

        NotificationCenter.default.post(
            name: .addTestPodcast,
            object: nil,
            userInfo: ["podcast": testPodcast]
        )

        debugLogger.info("Created test podcast: \(testPodcast.title, privacy: .public) with \(testPodcast.episodes.count, privacy: .public) episodes")
    }

    /// Creates a test podcast episode and posts a notification to add it to the queue.
    @MainActor
    func createTestEpisode() {
        let feed = "https://example.com/feed"
        guard
            let audioURL = URL(string: "https://example.com/test.mp3")
        else {
            debugLogger.error("❌ Invalid test episode URL")
            return
        }

        let testEpisode = PodcastEpisode(
            title: "Test Episode",
            url: audioURL,
            artworkURL: URL(string: "https://example.com/image.jpg"),
            duration: 600,
            showNotes: """
            This is a test episode with detailed show notes.

            It includes multiple paragraphs and formatting to test the show notes display.
            """,
            feedUrl: feed,
            podcastName: "Test Podcast"
        )

        NotificationCenter.default.post(
            name: .addTestEpisode,
            object: nil,
            userInfo: ["episode": testEpisode]
        )

        debugLogger.info("Created test episode: \(testEpisode.title, privacy: .public)")
    }
}
