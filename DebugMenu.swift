// Add a new menu item for testing FeedKit, somewhere around line 76

import SwiftUI
import OSLog

private let debugMenuLogger = AppLogger.debug

/// Provides a set of debug commands accessible via the app's menu.
/// Includes commands to run tests and create test data for rapid testing.
struct DebugCommands: Commands {
    var body: some Commands {
        // The "Debug" command menu contains test and data creation options.
        CommandMenu("Debug") {
            // Runs all tests when selected.
            Button("Run All Tests") {
                AppTests.runAllTests()
            }
            // Shortcut: Command + Option + T.
            .keyboardShortcut("t", modifiers: [.command, .option])
            
            Divider()  // Separates test commands from other options.
            
            // Runs the audio player test.
            Button("Test Audio Player") {
                do {
                    try AppTests.testAudioPlayer()
                } catch {
                    let errorDescription = String(describing: error)
                    debugMenuLogger.error("❌ Audio Player test failed: \(errorDescription, privacy: .public)")
                }
            }
            // Shortcut: Command + Option + 1.
            .keyboardShortcut("1", modifiers: [.command, .option])
            
            // Runs the player view test.
            Button("Test Player View") {
                do {
                    try AppTests.testPlayerView()
                } catch {
                    let errorDescription = String(describing: error)
                    debugMenuLogger.error("❌ Player View test failed: \(errorDescription, privacy: .public)")
                }
            }
            // Shortcut: Command + Option + 2.
            .keyboardShortcut("2", modifiers: [.command, .option])
            
            // Runs the download manager test.
            Button("Test Download Manager") {
                do {
                    try AppTests.testDownloadManager()
                } catch {
                    let errorDescription = String(describing: error)
                    debugMenuLogger.error("❌ Download Manager test failed: \(errorDescription, privacy: .public)")
                }
            }
            // Shortcut: Command + Option + 3.
            .keyboardShortcut("3", modifiers: [.command, .option])
            
            // Runs the podcast fetcher test.
            Button("Test Podcast Fetcher") {
                do {
                    try AppTests.testPodcastFetcher()
                } catch {
                    let errorDescription = String(describing: error)
                    debugMenuLogger.error("❌ Podcast Fetcher test failed: \(errorDescription, privacy: .public)")
                }
            }
            // Shortcut: Command + Option + 4.
            .keyboardShortcut("4", modifiers: [.command, .option])
            
            // Tests the FeedKit implementation
            Button("Test FeedKit Parser") {
                do {
                    try AppTests.testFeedKitIntegration()
                } catch {
                    let errorDescription = String(describing: error)
                    debugMenuLogger.error("❌ FeedKit test failed: \(errorDescription, privacy: .public)")
                }
            }
            // Shortcut: Command + Option + F.
            .keyboardShortcut("f", modifiers: [.command, .option])
            
            Divider()  // Separates test commands from creation commands.
            
            // Creates a test podcast with sample episodes.
            Button("Create Test Podcast") {
                createTestPodcast()
            }
            // Shortcut: Command + Option + P.
            .keyboardShortcut("p", modifiers: [.command, .option])
            
            // Creates a single test episode.
            Button("Create Test Episode") {
                createTestEpisode()
            }
            // Shortcut: Command + Option + E.
            .keyboardShortcut("e", modifiers: [.command, .option])
        }
    }
    
    /// Creates a test podcast populated with sample episodes.
    /// Posts a notification to add the test podcast to subscriptions.
    private func createTestPodcast() {
        // Instantiate a test podcast with a title and feed URL.
        let testPodcast = Podcast(
            title: "Test Podcast",
            feedUrl: "https://example.com/feed",
            episodes: []
        )
        // Set the podcast's artwork URL.
        testPodcast.feedArtworkURL = URL(string: "https://example.com/image.jpg")
        
        // Add sample episodes to the test podcast.
        for i in 1...5 {
            let episode = PodcastEpisode(
                title: "Test Episode \(i)",
                url: URL(string: "https://example.com/episode\(i).mp3")!,
                artworkURL: URL(string: "https://example.com/image\(i).jpg"),
                duration: Double(i * 300),
                showNotes: "This is test episode \(i)",
                feedUrl: "https://example.com/feed",
                podcastName: "Test Podcast"
            )
            testPodcast.episodes.append(episode)
        }
        
        // Notify the app to add the test podcast to the subscriptions.
        NotificationCenter.default.post(
            name: Notification.Name("AddTestPodcast"),
            object: nil,
            userInfo: ["podcast": testPodcast]
        )
        
        debugMenuLogger.info("Created test podcast: \(testPodcast.title, privacy: .public) with \(testPodcast.episodes.count, privacy: .public) episodes")
    }
    
    /// Creates a test podcast episode and posts a notification to add it to the play queue.
    private func createTestEpisode() {
        let testEpisode = PodcastEpisode(
            title: "Test Episode",
            url: URL(string: "https://example.com/test.mp3")!,
            artworkURL: URL(string: "https://example.com/image.jpg"),
            duration: 600,
            showNotes: "This is a test episode with detailed show notes.\n\nIt includes multiple paragraphs and formatting to test the show notes display.",
            feedUrl: "https://example.com/feed",
            podcastName: "Test Podcast"
        )
        
        // Post a notification to add the test episode to the cue.
        NotificationCenter.default.post(
            name: Notification.Name("AddTestEpisode"),
            object: nil,
            userInfo: ["episode": testEpisode]
        )
        
        debugMenuLogger.info("Created test episode: \(testEpisode.title, privacy: .public)")
    }
}
