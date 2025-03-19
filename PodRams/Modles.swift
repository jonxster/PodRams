//
//  Modles.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine

class Podcast: Identifiable, Equatable, ObservableObject, @unchecked Sendable {
    let id = UUID() // internal identity for podcasts
    var title: String
    let feedUrl: String?
    @Published var episodes: [PodcastEpisode]
    var feedArtworkURL: URL?

    init(title: String, feedUrl: String?, episodes: [PodcastEpisode] = []) {
        self.title = title
        self.feedUrl = feedUrl
        self.episodes = episodes
    }

    static func == (lhs: Podcast, rhs: Podcast) -> Bool {
        lhs.id == rhs.id
    }
}

struct PodcastEpisode: Identifiable, Equatable, Codable {
    // If no id is provided, use url.absoluteString as a stable identifier.
    let id: String
    let title: String
    let url: URL
    let artworkURL: URL?
    var duration: Double?
    let showNotes: String?
    let feedUrl: String?
    var podcastName: String? // Holds the parent podcast's title

    init(id: String? = nil, title: String, url: URL, artworkURL: URL?, duration: Double?, showNotes: String?, feedUrl: String? = nil, podcastName: String? = nil) {
        self.id = id ?? url.absoluteString
        self.title = title
        self.url = url
        self.artworkURL = artworkURL
        self.duration = duration
        self.showNotes = showNotes
        self.feedUrl = feedUrl
        self.podcastName = podcastName
    }
    
    // Add coding keys to handle URL encoding/decoding
    enum CodingKeys: String, CodingKey {
        case id, title, url, artworkURL, duration, showNotes, feedUrl, podcastName
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
    }
    
    static func == (lhs: PodcastEpisode, rhs: PodcastEpisode) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.url.absoluteString == rhs.url.absoluteString &&
        lhs.artworkURL?.absoluteString == rhs.artworkURL?.absoluteString &&
        lhs.duration == rhs.duration &&
        lhs.showNotes == rhs.showNotes &&
        lhs.feedUrl == rhs.feedUrl
    }
}

struct PodcastSearchResponse: Codable {
    let resultCount: Int
    let results: [PodcastResult]
}

struct PodcastResult: Codable {
    let collectionName: String
    let feedUrl: String?
    let artworkUrl600: String?
}
