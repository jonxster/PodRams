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

struct PodcastEpisode: Identifiable, Equatable {
    // If no id is provided, use url.absoluteString as a stable identifier.
    let id: String
    let title: String
    let url: URL
    let artworkURL: URL?
    var duration: Double?
    let showNotes: String?
    let feedUrl: String?
    var podcastName: String? // Holds the parent podcast’s title

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
