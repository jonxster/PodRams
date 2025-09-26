import Foundation
#if canImport(FeedKit)
@preconcurrency import FeedKit
#endif

/// Test function to validate FeedKit integration
/// Add this to the AppTests class to test FeedKit functionality
extension AppTests {
    static func testFeedKitIntegration() throws {
        print("Testing FeedKit Integration...")
        
        // Create a sample RSS feed
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
            <channel>
                <title>Test FeedKit Podcast</title>
                <itunes:image href="https://example.com/image.jpg"/>
                <item>
                    <title>FeedKit Episode 1</title>
                    <enclosure url="https://example.com/episode1.mp3" type="audio/mpeg" length="12345"/>
                    <itunes:duration>1:30:45</itunes:duration>
                    <description>This is FeedKit episode 1</description>
                </item>
                <item>
                    <title>FeedKit Episode 2</title>
                    <enclosure url="https://example.com/episode2.mp3" type="audio/mpeg" length="67890"/>
                    <itunes:duration>45:30</itunes:duration>
                    <description>This is FeedKit episode 2</description>
                </item>
            </channel>
        </rss>
        """
        
        let data = rssXML.data(using: .utf8)!
        
        // Test the new FeedKitRSSParser
        #if canImport(FeedKit)
        do {
            print("- Testing FeedKitRSSParser...")
            let parser = FeedKitRSSParser(feedUrl: "https://example.com/feed")
            let (episodes, feedArtwork, channelTitle) = parser.parse(data: data)
            
            // Verify the parsed data
            safeAssert(channelTitle == "Test FeedKit Podcast", "Channel title should be 'Test FeedKit Podcast'")
            safeAssert(feedArtwork?.absoluteString == "https://example.com/image.jpg", 
                   "Feed artwork URL should be correct")
            safeAssert(episodes.count == 2, "Should parse 2 episodes")
            
            // Verify the first episode
            safeAssert(episodes[0].title == "FeedKit Episode 1", "First episode title should be 'FeedKit Episode 1'")
            safeAssert(episodes[0].url.absoluteString == "https://example.com/episode1.mp3", 
                   "First episode URL should be correct")
            
            print("- FeedKitRSSParser tests passed!")
        } catch {
            print("- FeedKitRSSParser test failed with error: \(error)")
        }
        #else
        print("- FeedKit is not available, skipping FeedKitRSSParser test")
        #endif
        
        // Test the legacy RSSParser for comparison
        do {
            print("- Testing legacy RSSParser...")
            let parser = RSSParser(feedUrl: "https://example.com/feed")
            let (episodes, feedArtwork, channelTitle) = parser.parse(data: data)
            
            // Verify the parsed data
            safeAssert(channelTitle == "Test FeedKit Podcast", "Channel title should be 'Test FeedKit Podcast'")
            safeAssert(feedArtwork?.absoluteString == "https://example.com/image.jpg", 
                   "Feed artwork URL should be correct")
            safeAssert(episodes.count == 2, "Should parse 2 episodes")
            
            // Verify the first episode
            safeAssert(episodes[0].title == "FeedKit Episode 1", "First episode title should be 'FeedKit Episode 1'")
            safeAssert(episodes[0].url.absoluteString == "https://example.com/episode1.mp3", 
                   "First episode URL should be correct")
            
            print("- Legacy RSSParser tests passed!")
        } catch {
            print("- Legacy RSSParser test failed with error: \(error)")
        }
        
        print("FeedKit Integration tests completed!")
    }
} 
