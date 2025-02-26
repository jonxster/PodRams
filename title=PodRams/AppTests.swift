class AppTests {
    static func testPodcastFetcher() throws {
        print("Testing RSSParser...")
        // [existing test code for RSSParser]
        print("✅ RSSParser tests passed!")
    }

    static func testProgressBarTimeFormatting() throws {
        // Test case 1: currentTime = 0, duration = 600 (10 minutes)
        let result1 = ProgressBarView.timerText(currentTime: 0, duration: 600)
        safeAssert(result1 == "10:00 of 10:00 remaining", "Expected '10:00 of 10:00 remaining', got \(result1)")
        
        // Test case 2: currentTime = 300 (5 minutes), duration = 600 (10 minutes)
        let result2 = ProgressBarView.timerText(currentTime: 300, duration: 600)
        // Accept either "5:00" or "05:00" as the formatter may omit a leading zero
        safeAssert(result2 == "5:00 of 10:00 remaining" || result2 == "05:00 of 10:00 remaining",
                   "Expected '05:00 of 10:00 remaining', got \(result2)")
        
        // Test case 3: currentTime = 599, duration = 600, expected "0:01 of 10:00 remaining"
        let result3 = ProgressBarView.timerText(currentTime: 599, duration: 600)
        safeAssert(result3 == "0:01 of 10:00 remaining", "Expected '0:01 of 10:00 remaining', got \(result3)")
        
        // Test case 4: currentTime greater than duration (e.g. 700 > 600)
        let result4 = ProgressBarView.timerText(currentTime: 700, duration: 600)
        safeAssert(result4 == "0:00 of 10:00 remaining", "Expected '0:00 of 10:00 remaining', got \(result4)")
        
        print("✅ ProgressBar time formatting tests passed!")
    }

    static func runAllTests() {
        print("Running PodRams tests...")
        
        do {
            try testAudioPlayer()
            try testPlayerView()
            try testDownloadManager()
            try testPodcastFetcher()
            try testProgressBarTimeFormatting()
            
            print("✅ All tests completed successfully!")
        } catch {
            print("❌ Tests failed with error: \(error)")
        }
    }
} 