import Foundation
import FeedKit

/// RSSParser implementation using FeedKit for improved podcast feed parsing
class FeedKitRSSParser {
    private let feedUrl: String
    
    init(feedUrl: String) {
        self.feedUrl = feedUrl
    }
    
    /// Parse RSS feed data and extract podcast episodes, artwork URL, and channel title
    func parse(data: Data) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        // Assume initializer succeeds if FeedKit is imported
        let parser = FeedParser(data: data)
        
        // Attempt to parse
        let result = parser.parse()
        
        switch result {
        case .success(let feed):
            if let rssFeed = feed.rssFeed {
                // Call the private instance method
                return parseRSSFeed(rssFeed)
            } else if let atomFeed = feed.atomFeed {
                // Call the private instance method
                return parseAtomFeed(atomFeed)
            } else if let jsonFeed = feed.jsonFeed {
                // Call the private instance method
                return parseJSONFeed(jsonFeed)
            } else {
                print("Feed format not recognized")
                return ([], nil, nil)
            }
            
        case .failure(let error):
            // Use _ to silence the unused variable warning
            print("FeedKit parsing error: \(error)")
            return ([], nil, nil)
        }
    }
    
    // MARK: - Private Parsing Helpers
    
    /// Parse RSS feed
    private func parseRSSFeed(_ feed: RSSFeed) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        var episodes: [PodcastEpisode] = []
        var feedArtworkURL: URL? = nil
        let channelTitle = feed.title
        
        // Get feed artwork from iTunes image
        if let imageUrl = feed.iTunes?.iTunesImage?.attributes?.href {
            feedArtworkURL = URL(string: imageUrl)
        } else if let imageUrl = feed.image?.url {
            feedArtworkURL = URL(string: imageUrl)
        }
        
        // Parse episodes from the first 10 items
        if let items = feed.items {
            for item in items.prefix(10) { // Limit to first 10
                // Call the private instance method
                if let episode = createEpisodeFromRSSItem(item) {
                    episodes.append(episode)
                }
            }
        }
        
        return (episodes, feedArtworkURL, channelTitle)
    }
    
    /// Parse Atom feed
    private func parseAtomFeed(_ feed: AtomFeed) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        var episodes: [PodcastEpisode] = []
        let channelTitle = feed.title
        var feedArtworkURL: URL? = nil
        
        // Find feed artwork from icon or logo
        if let iconString = feed.icon {
            feedArtworkURL = URL(string: iconString)
        } else if let logoString = feed.logo {
            feedArtworkURL = URL(string: logoString)
        }
        
        // Parse episodes from the first 10 entries
        if let entries = feed.entries {
            for entry in entries.prefix(10) { // Limit to first 10
                // Call the private instance method
                if let episode = createEpisodeFromAtomEntry(entry) {
                    episodes.append(episode)
                }
            }
        }
        
        return (episodes, feedArtworkURL, channelTitle)
    }
    
    /// Parse JSON Feed
    private func parseJSONFeed(_ feed: JSONFeed) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        var episodes: [PodcastEpisode] = []
        let channelTitle = feed.title
        var feedArtworkURL: URL? = nil
        
        // Find feed artwork
        if let iconString = feed.icon {
            feedArtworkURL = URL(string: iconString)
        } else if let faviconString = feed.favicon {
            feedArtworkURL = URL(string: faviconString)
        }
        
        // Parse episodes from the first 10 items
        if let items = feed.items {
            for item in items.prefix(10) { // Limit to first 10
                // Call the private instance method
                if let episode = createEpisodeFromJSONItem(item) {
                    episodes.append(episode)
                }
            }
        }
        
        return (episodes, feedArtworkURL, channelTitle)
    }
    
    /// Create a PodcastEpisode from an RSS item
    private func createEpisodeFromRSSItem(_ item: RSSFeedItem) -> PodcastEpisode? {
        guard let title = item.title else {
            return nil
        }
        
        // Find audio URL from enclosure
        guard let enclosure = item.enclosure,
              let urlString = enclosure.attributes?.url,
              let audioURL = URL(string: urlString) else {
            return nil
        }
        
        // Get artwork URL from iTunes image or media content
        var artworkURL: URL? = nil
        if let itunesImage = item.iTunes?.iTunesImage?.attributes?.href {
            artworkURL = URL(string: itunesImage)
        } else if let mediaContent = item.media?.mediaContents?.first,
                  let mediaUrl = mediaContent.attributes?.url,
                  mediaContent.attributes?.medium == "image" {
            artworkURL = URL(string: mediaUrl)
        }
        
        // Get duration directly from iTunes duration (it's already a Double/TimeInterval)
        let duration = item.iTunes?.iTunesDuration
        
        // Get show notes from description or content
        var showNotes: String? = nil
        if let description = item.description {
            showNotes = description.htmlStripped
        } else if let content = item.content?.contentEncoded {
            showNotes = content.htmlStripped
        }
        
        return PodcastEpisode(
            title: title,
            url: audioURL,
            artworkURL: artworkURL,
            duration: duration, // Assign directly
            showNotes: showNotes,
            feedUrl: feedUrl
        )
    }
    
    /// Create a PodcastEpisode from an Atom entry
    private func createEpisodeFromAtomEntry(_ entry: AtomFeedEntry) -> PodcastEpisode? {
        guard let title = entry.title else {
            return nil
        }
        
        // Find audio URL from link with audio type
        guard let links = entry.links,
              let audioLink = links.first(where: { $0.attributes?.type?.starts(with: "audio/") ?? false }),
              let urlString = audioLink.attributes?.href,
              let audioURL = URL(string: urlString) else {
            return nil
        }
        
        // Get artwork URL from any image link
        var artworkURL: URL? = nil
        if let imageLink = entry.links?.first(where: { $0.attributes?.type?.starts(with: "image/") ?? false }),
           let imageUrlString = imageLink.attributes?.href {
            artworkURL = URL(string: imageUrlString)
        }
        
        // Get show notes from content
        var showNotes: String? = nil
        if let content = entry.content?.value {
            showNotes = content.htmlStripped
        } else if let summary = entry.summary?.value {
            showNotes = summary.htmlStripped
        }
        
        return PodcastEpisode(
            title: title,
            url: audioURL,
            artworkURL: artworkURL,
            duration: nil, // Atom feeds typically don't include duration
            showNotes: showNotes,
            feedUrl: feedUrl
        )
    }
    
    /// Create a PodcastEpisode from a JSON Feed item
    private func createEpisodeFromJSONItem(_ item: JSONFeedItem) -> PodcastEpisode? {
        guard let title = item.title else {
            return nil
        }
        
        // Find audio URL from attachments with audio type
        guard let attachments = item.attachments,
              let audioAttachment = attachments.first(where: { $0.mimeType?.starts(with: "audio/") ?? false }),
              let urlString = audioAttachment.url,
              let audioURL = URL(string: urlString) else {
            return nil
        }
        
        // Get artwork URL from image
        var artworkURL: URL? = nil
        if let imageUrlString = item.image {
            artworkURL = URL(string: imageUrlString)
        }
        
        // Get show notes from content_html or content_text
        var showNotes: String? = nil
        if let contentHtml = item.contentHtml {
            showNotes = contentHtml.htmlStripped
        } else if let contentText = item.contentText {
            showNotes = contentText
        } else if let summary = item.summary {
            showNotes = summary
        }
        
        // Get duration from attachment duration if available
        var duration: Double? = nil
        if let attachments = item.attachments,
           let audioAttachment = attachments.first(where: { $0.mimeType?.starts(with: "audio/") ?? false }),
           let durationSeconds = audioAttachment.durationInSeconds {
            duration = Double(durationSeconds)
        }
        
        return PodcastEpisode(
            title: title,
            url: audioURL,
            artworkURL: artworkURL,
            duration: duration,
            showNotes: showNotes,
            feedUrl: feedUrl
        )
    }
    
    /// Parse duration string to seconds (Only needed if duration is provided as a string)
    private func parseDuration(_ durationString: String) -> Double {
        let trimmed = durationString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0.0
        }
        
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map { String($0) }
            var seconds = 0.0
            
            switch parts.count {
            case 3: // HH:MM:SS
                if let hours = Double(parts[0]),
                   let minutes = Double(parts[1]),
                   let secs = Double(parts[2]) {
                    seconds = (hours * 3600) + (minutes * 60) + secs
                }
            case 2: // MM:SS
                if let minutes = Double(parts[0]),
                   let secs = Double(parts[1]) {
                    seconds = (minutes * 60) + secs
                }
            case 1:
                if let secs = Double(parts[0]) {
                    seconds = secs
                }
            default:
                return 0.0
            }
            return seconds.isFinite && seconds >= 0 ? seconds : 0.0
        } else {
            if let seconds = Double(trimmed), seconds >= 0 {
                return seconds
            }
            return 0.0
        }
    }
} 