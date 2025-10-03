import OSLog

private let minimalTestLogger = AppLogger.tests

static func runAllTests() {
    minimalTestLogger.info("Running PodRams tests...")
    
    do {
        try testAudioPlayer()
        try testPlayerView()
        try testDownloadManager()
        try testPodcastFetcher()
        try testEpisodeRowHover()
        try testProgressBarTimeFormatting()
        try testFeedKitIntegration()
        
        minimalTestLogger.info("✅ All tests completed successfully!")
    } catch {
        let errorDescription = String(describing: error)
        minimalTestLogger.error("❌ Tests failed with error: \(errorDescription, privacy: .public)")
    }
} 
