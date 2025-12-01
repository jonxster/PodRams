//
//  Modles.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import OSLog

private let modelLogger = AppLogger.app

@MainActor
final class Podcast: Identifiable, Equatable, ObservableObject {
    let id = UUID() // internal identity for podcasts
    var title: String
    let feedUrl: String?
    @Published var episodes: [PodcastEpisode]
    @Published var feedArtworkURL: URL?

    init(title: String, feedUrl: String?, episodes: [PodcastEpisode] = [], feedArtworkURL: URL? = nil) {
        self.title = title
        self.feedUrl = feedUrl
        self.episodes = episodes
        self.feedArtworkURL = feedArtworkURL
    }

    nonisolated static func == (lhs: Podcast, rhs: Podcast) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Optimizes memory usage by limiting episode count and cleaning up data
    /// Reduces memory footprint for podcast collections
    func optimizeMemoryUsage() async {
        // Memory optimization: Limit episodes to most recent 50 to reduce memory usage
        let manager = MemoryOptimizationManager.shared
        let maxEpisodes = max(manager.maxEpisodesPerPodcast * 3, 20)
        if episodes.count > maxEpisodes {
            // Keep only the most recent episodes (assuming they're ordered by date)
            episodes = Array(episodes.prefix(maxEpisodes))
            modelLogger.info("Memory optimization: Limited \(self.title, privacy: .private) to \(maxEpisodes, privacy: .public) episodes")
        }
        
        // Optimize episode data
        for i in episodes.indices {
            episodes[i] = optimizeEpisode(episodes[i])
        }
    }
    
    /// Optimizes individual episode data to reduce memory usage
    private func optimizeEpisode(_ episode: PodcastEpisode) -> PodcastEpisode {
        // Truncate overly long show notes to reduce memory usage
        var optimizedShowNotes = episode.showNotes
        if let notes = episode.showNotes,
           notes.count > MemoryOptimizationManager.shared.maxShowNotesLength {
            // Keep first N characters with ellipsis
            let limit = MemoryOptimizationManager.shared.maxShowNotesLength
            let truncated = String(notes.prefix(limit)) + "..."
            optimizedShowNotes = truncated
        }
        
        // Create new optimized episode if changes were made
        if optimizedShowNotes != episode.showNotes {
            return PodcastEpisode(
                id: episode.id,
                title: episode.title,
                url: episode.url,
                artworkURL: episode.artworkURL,
                duration: episode.duration,
                showNotes: optimizedShowNotes,
                feedUrl: episode.feedUrl,
                podcastName: episode.podcastName
            )
        }
        
        return episode
    }
    
    /// Calculates estimated memory usage of this podcast
    func estimatedMemoryUsage() -> Int {
        var totalSize = 0
        
        // Basic object overhead
        totalSize += 64 // Base object size
        
        // Title and feed URL
        totalSize += title.utf8.count
        totalSize += feedUrl?.utf8.count ?? 0
        
        // Episodes collection
        totalSize += episodes.count * 8 // Array overhead
        for episode in episodes {
            totalSize += episode.estimatedMemoryUsage()
        }
        
        return totalSize
    }
}

struct Chapter: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let title: String
    let startTime: Double
    let endTime: Double
    
    init(title: String, startTime: Double, endTime: Double) {
        self.id = UUID()
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct PodcastEpisode: Identifiable, Equatable, Codable, Sendable {
    // If no id is provided, use url.absoluteString as a stable identifier.
    let id: String
    let title: String
    let url: URL
    let artworkURL: URL?
    var duration: Double?
    let showNotes: String?
    let feedUrl: String?
    var podcastName: String? // Holds the parent podcast's title
    var chapters: [Chapter]?

    init(id: String? = nil, title: String, url: URL, artworkURL: URL?, duration: Double?, showNotes: String?, feedUrl: String? = nil, podcastName: String? = nil, chapters: [Chapter]? = nil) {
        self.id = id ?? url.absoluteString
        self.title = title
        self.url = url
        self.artworkURL = artworkURL
        self.duration = duration
        self.showNotes = showNotes
        self.feedUrl = feedUrl
        self.podcastName = podcastName
        self.chapters = chapters
    }
    
    // Add coding keys to handle URL encoding/decoding
    enum CodingKeys: String, CodingKey {
        case id, title, url, artworkURL, duration, showNotes, feedUrl, podcastName, chapters
    }
    
    // Custom encoding to handle URL properties
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url.absoluteString, forKey: .url)
        try container.encode(artworkURL?.absoluteString, forKey: .artworkURL)
        try container.encode(duration, forKey: .duration)
        try container.encode(showNotes, forKey: .showNotes)
        try container.encode(feedUrl, forKey: .feedUrl)
        try container.encode(podcastName, forKey: .podcastName)
        try container.encodeIfPresent(chapters, forKey: .chapters)
    }
    
    // Custom decoding to handle URL properties
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let urlString = try container.decode(String.self, forKey: .url)
        guard let decodedUrl = URL(string: urlString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Invalid URL string")
        }
        url = decodedUrl
        
        let artworkURLString = try container.decodeIfPresent(String.self, forKey: .artworkURL)
        artworkURL = artworkURLString.flatMap { URL(string: $0) }
        
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        showNotes = try container.decodeIfPresent(String.self, forKey: .showNotes)
        feedUrl = try container.decodeIfPresent(String.self, forKey: .feedUrl)
        podcastName = try container.decodeIfPresent(String.self, forKey: .podcastName)
        chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters)
    }
    
    static func == (lhs: PodcastEpisode, rhs: PodcastEpisode) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.url.absoluteString == rhs.url.absoluteString &&
        lhs.artworkURL?.absoluteString == rhs.artworkURL?.absoluteString &&
        lhs.duration == rhs.duration &&
        lhs.showNotes == rhs.showNotes &&
        lhs.feedUrl == rhs.feedUrl &&
        lhs.chapters == rhs.chapters
    }
    
    /// Calculates estimated memory usage of this episode
    func estimatedMemoryUsage() -> Int {
        var totalSize = 0
        
        // Basic object overhead
        totalSize += 64 // Base object size
        
        // Title and URL
        totalSize += title.utf8.count
        totalSize += url.absoluteString.utf8.count
        
        // Artwork URL
        totalSize += artworkURL?.absoluteString.utf8.count ?? 0
        
        // Duration
        totalSize += duration.map { _ in 8 } ?? 0
        
        // Show notes
        totalSize += showNotes?.utf8.count ?? 0
        
        // Chapters
        if let chapters = chapters {
            totalSize += chapters.count * 32 // rough estimate
        }
        
        return totalSize
    }
}

struct PodcastSearchResponse: Codable, Sendable {
    let resultCount: Int
    let results: [PodcastResult]
}

struct PodcastResult: Codable, Sendable {
    let collectionName: String
    let feedUrl: String?
    let artworkUrl600: String?
}
