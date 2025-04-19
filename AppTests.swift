static func runAllTests() {
    print("Running PodRams tests...")
    
    do {
        try testAudioPlayer()
        try testPlayerView()
        try testDownloadManager()
        try testPodcastFetcher()
        try testEpisodeRowHover()
        try testProgressBarTimeFormatting()
        try testFeedKitIntegration()
        
        print("✅ All tests completed successfully!")
    } catch {
        print("❌ Tests failed with error: \(error)")
    }
} 