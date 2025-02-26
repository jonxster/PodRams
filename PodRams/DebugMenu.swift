//
//  DebugMenu.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI

struct DebugCommands: Commands {
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Run All Tests") {
                AppTests.runAllTests()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            
            Divider()
            
            Button("Test Audio Player") {
                do {
                    try AppTests.testAudioPlayer()
                } catch {
                    print("❌ Audio Player test failed: \(error)")
                }
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            
            Button("Test Player View") {
                do {
                    try AppTests.testPlayerView()
                } catch {
                    print("❌ Player View test failed: \(error)")
                }
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            
            Button("Test Download Manager") {
                do {
                    try AppTests.testDownloadManager()
                } catch {
                    print("❌ Download Manager test failed: \(error)")
                }
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            
            Button("Test Podcast Fetcher") {
                do {
                    try AppTests.testPodcastFetcher()
                } catch {
                    print("❌ Podcast Fetcher test failed: \(error)")
                }
            }
            .keyboardShortcut("4", modifiers: [.command, .option])
            
            Divider()
            
            Button("Create Test Podcast") {
                createTestPodcast()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            
            Button("Create Test Episode") {
                createTestEpisode()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
        }
    }
    
    // Helper function to create a test podcast
    private func createTestPodcast() {
        let testPodcast = Podcast(
            title: "Test Podcast",
            feedUrl: "https://example.com/feed",
            episodes: []
        )
        testPodcast.feedArtworkURL = URL(string: "https://example.com/image.jpg")
        
        // Add some test episodes
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
        
        // Add to subscriptions
        NotificationCenter.default.post(
            name: Notification.Name("AddTestPodcast"),
            object: nil,
            userInfo: ["podcast": testPodcast]
        )
        
        print("Created test podcast: \(testPodcast.title) with \(testPodcast.episodes.count) episodes")
    }
    
    // Helper function to create a test episode
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
        
        // Add to queue
        NotificationCenter.default.post(
            name: Notification.Name("AddTestEpisode"),
            object: nil,
            userInfo: ["episode": testEpisode]
        )
        
        print("Created test episode: \(testEpisode.title)")
    }
} 