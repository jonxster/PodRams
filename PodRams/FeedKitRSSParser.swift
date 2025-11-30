import Foundation
@preconcurrency import FeedKit
import OSLog

private let feedLogger = AppLogger.feed

/// RSSParser implementation using FeedKit for improved podcast feed parsing
class FeedKitRSSParser {
    private let feedUrl: String
    
    init(feedUrl: String) {
        self.feedUrl = feedUrl
    }
    
    /// Parse RSS feed data and extract podcast episodes, artwork URL, and channel title
    func parse(data: Data) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        do {
            let feed = try Feed(data: data)
            switch feed {
            case .rss(let rssFeed):
                return parseRSSFeed(rssFeed)
            case .atom(let atomFeed):
                return parseAtomFeed(atomFeed)
            case .json(let jsonFeed):
                return parseJSONFeed(jsonFeed)
            }
        } catch {
            feedLogger.error("FeedKit parsing error: \(error, privacy: .public)")
            return ([], nil, nil)
        }
    }
    
    // MARK: - Private Parsing Helpers
    
    /// Parse RSS feed
    private func parseRSSFeed(_ feed: RSSFeed) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        guard let channel = feed.channel else {
            feedLogger.error("RSS feed missing channel")
            return ([], nil, nil)
        }
        
        var episodes: [PodcastEpisode] = []
        var feedArtworkURL: URL? = nil
        let channelTitle = channel.title
        
        // Get feed artwork from iTunes image
        if let imageUrl = channel.iTunes?.image?.attributes?.href {
            feedArtworkURL = URL(string: imageUrl)
        } else if let imageUrl = channel.image?.url {
            feedArtworkURL = URL(string: imageUrl)
        }
        
        // Parse episodes from the first 15 items for better performance
        let items = channel.items ?? []
        let limitedItems = items.prefix(15) // Increase from 10 to 15 but still limit
        for item in limitedItems {
            if let episode = createEpisodeFromRSSItem(item, podcastTitle: channelTitle) {
                episodes.append(episode)
            }
            // Early break if we have enough episodes
            if episodes.count >= 10 {
                break
            }
        }
        
        return (episodes, feedArtworkURL, channelTitle)
    }
    
    /// Parse Atom feed
    private func parseAtomFeed(_ feed: AtomFeed) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        var episodes: [PodcastEpisode] = []
        let channelTitle = feed.title?.text
        var feedArtworkURL: URL? = nil
        
        // Find feed artwork from icon or logo
        if let iconString = feed.icon {
            feedArtworkURL = URL(string: iconString)
        } else if let logoString = feed.logo {
            feedArtworkURL = URL(string: logoString)
        }
        
        // Parse episodes from the first 15 entries for better performance
        let entries = feed.entries ?? []
        let limitedEntries = entries.prefix(15)
        for entry in limitedEntries {
            if let episode = createEpisodeFromAtomEntry(entry, podcastTitle: channelTitle) {
                episodes.append(episode)
            }
            // Early break if we have enough episodes
            if episodes.count >= 10 {
                break
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
        
        // Parse episodes from the first 15 items for better performance
        if let items = feed.items {
            let limitedItems = items.prefix(15)
            for item in limitedItems {
                if let episode = createEpisodeFromJSONItem(item, podcastTitle: channelTitle) {
                    episodes.append(episode)
                }
                // Early break if we have enough episodes
                if episodes.count >= 10 {
                    break
                }
            }
        }
        
        return (episodes, feedArtworkURL, channelTitle)
    }
    
    /// Create a PodcastEpisode from an RSS item
    private func createEpisodeFromRSSItem(_ item: RSSFeedItem, podcastTitle: String?) -> PodcastEpisode? {
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
        if let itunesImage = item.iTunes?.image?.attributes?.href {
            artworkURL = URL(string: itunesImage)
        } else if let thumbnailUrl = item.media?.thumbnails?.first?.attributes?.url {
            artworkURL = URL(string: thumbnailUrl)
        } else if let mediaContent = item.media?.contents?.first(where: { content in
            let medium = content.attributes?.medium?.lowercased()
            let type = content.attributes?.type?.lowercased()
            return medium == "image" || (type?.hasPrefix("image/") ?? false)
        })?.attributes?.url {
            artworkURL = URL(string: mediaContent)
        }
        
        // Get duration directly from iTunes duration (it's already a Double/TimeInterval)
        let duration = item.iTunes?.duration ?? item.media?.contents?.first?.attributes?.duration.map(Double.init)
        
        // Get show notes from description or content
        var showNotes: String? = nil
        if let description = item.description {
            showNotes = description.htmlStripped
        } else if let content = item.content?.encoded {
            showNotes = content.htmlStripped
        }
        
        return PodcastEpisode(
            title: title,
            url: audioURL,
            artworkURL: artworkURL,
            duration: duration, // Assign directly
            showNotes: showNotes,
            feedUrl: feedUrl,
            podcastName: podcastTitle
        )
    }
    
    /// Create a PodcastEpisode from an Atom entry
    private func createEpisodeFromAtomEntry(_ entry: AtomFeedEntry, podcastTitle: String?) -> PodcastEpisode? {
        guard let title = entry.title else {
            return nil
        }
        
        // Find audio URL from link with audio type
        guard let links = entry.links,
              let audioLink = links.first(where: { link in
                  guard let attributes = link.attributes else { return false }
                  let type = attributes.type?.lowercased() ?? ""
                  if type.hasPrefix("audio/") {
                      return true
                  }
                  if let rel = attributes.rel?.lowercased(), rel == "enclosure" {
                      return true
                  }
                  return false
              }),
              let urlString = audioLink.attributes?.href,
              let audioURL = URL(string: urlString) else {
            return nil
        }
        
        // Get artwork URL from any image link
        var artworkURL: URL? = nil
        if let imageLink = entry.links?.first(where: { $0.attributes?.type?.starts(with: "image/") ?? false }),
           let imageUrlString = imageLink.attributes?.href {
            artworkURL = URL(string: imageUrlString)
        } else if let mediaThumbnail = entry.media?.thumbnails?.first?.attributes?.url {
            artworkURL = URL(string: mediaThumbnail)
        }
        
        let duration = entry.media?.contents?.first(where: { $0.attributes?.type?.starts(with: "audio/") ?? false })?.attributes?.duration.map(Double.init)
        
        // Get show notes from content
        var showNotes: String? = nil
        if let content = entry.content?.text {
            showNotes = content.htmlStripped
        } else if let summary = entry.summary?.text {
            showNotes = summary.htmlStripped
        }
        
        return PodcastEpisode(
            title: title,
            url: audioURL,
            artworkURL: artworkURL,
            duration: duration,
            showNotes: showNotes,
            feedUrl: feedUrl,
            podcastName: podcastTitle
        )
    }
    
    /// Create a PodcastEpisode from a JSON Feed item
    private func createEpisodeFromJSONItem(_ item: JSONFeedItem, podcastTitle: String?) -> PodcastEpisode? {
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
        if let imageUrlString = item.image ?? item.bannerImage {
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
        let duration = audioAttachment.durationInSeconds
        
        return PodcastEpisode(
            title: title,
            url: audioURL,
            artworkURL: artworkURL,
            duration: duration,
            showNotes: showNotes,
            feedUrl: feedUrl,
            podcastName: podcastTitle
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
