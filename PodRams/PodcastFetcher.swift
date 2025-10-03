//
//  PodcastFetcher.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// PodcastFetcher.swift

import Foundation
import Combine
import AVFoundation
@preconcurrency import FeedKit
import OSLog

private let podcastFetcherLogger = AppLogger.networking

@MainActor
final class PodcastFetcher: ObservableObject {
    @Published var searchQuery = ""
    @Published var podcasts: [Podcast] = []
    
    // Optimized cache sizes to reduce memory usage
    private var searchCache: [String: [Podcast]] = [:]
    private var episodeCache: [String: (episodes: [PodcastEpisode], feedArtwork: URL?)] = [:]
    
    // Memory optimization settings
    private let maxSearchCacheSize = 20 // Reduced from 50
    private let maxEpisodeCacheSize = 10 // Reduced from 20
    private let maxEpisodesPerFeed = 10 // Limit episodes to save memory
    
    init() {
        // Listen for memory optimization notifications
        NotificationCenter.default.addObserver(
            forName: Notification.Name("CleanRSSFeedCache"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearCaches()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func searchPodcasts() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let cached = searchCache[query] {
            podcasts = cached
            return
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=podcast&term=\(encodedQuery)&entity=podcast&limit=25") else {
            podcastFetcherLogger.error("Invalid search query")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PodcastSearchResponse.self, from: data)

            let results = response.results.compactMap { result -> Podcast? in
                guard let feedUrl = result.feedUrl else { return nil }
                let podcast = Podcast(title: result.collectionName, feedUrl: feedUrl)
                if let art = result.artworkUrl600, let artURL = MediaURLSanitizer.sanitize(art) {
                    podcast.feedArtworkURL = artURL
                }
                return podcast
            }

            searchCache[query] = results
            if searchCache.count > maxSearchCacheSize {
                let overflow = searchCache.count - maxSearchCacheSize
                let keysToRemove = Array(searchCache.keys.prefix(overflow))
                for key in keysToRemove {
                    searchCache.removeValue(forKey: key)
                }
            }

            podcasts = results
        } catch {
            podcastFetcherLogger.error("Error fetching podcasts: \(error, privacy: .public)")
        }
    }
    
    func fetchEpisodes(for podcast: Podcast) async {
        guard let feedUrlString = podcast.feedUrl,
              let sanitizedFeedURL = MediaURLSanitizer.sanitize(feedUrlString) else {
            podcastFetcherLogger.error("Invalid feed URL")
            return
        }

        let cacheKey = sanitizedFeedURL.absoluteString

        guard shouldAttemptNetwork(for: sanitizedFeedURL) else {
            podcastFetcherLogger.warning("Skipping episode fetch for unresolved host: \(feedUrlString, privacy: .private)")
            return
        }

        if let cached = episodeCache[cacheKey] ?? episodeCache[feedUrlString] {
            podcast.episodes = Array(cached.episodes.prefix(maxEpisodesPerFeed))
            if let feedArt = cached.feedArtwork {
                podcast.feedArtworkURL = feedArt
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: sanitizedFeedURL)

            let parser = FeedKitRSSParser(feedUrl: cacheKey)
            let (allEpisodes, feedArt, channelTitle) = parser.parse(data: data)

            let limitedEpisodes = Array(allEpisodes.prefix(maxEpisodesPerFeed))

            episodeCache[cacheKey] = (limitedEpisodes, feedArt)
            if episodeCache.count > maxEpisodeCacheSize {
                let overflow = episodeCache.count - maxEpisodeCacheSize
                let keysToRemove = Array(episodeCache.keys.prefix(overflow))
                for key in keysToRemove {
                    episodeCache.removeValue(forKey: key)
                }
            }

            podcast.episodes = limitedEpisodes
            if let feedArt = feedArt {
                podcast.feedArtworkURL = feedArt
            }
            if let channelTitle = channelTitle, !channelTitle.isEmpty {
                podcast.title = channelTitle
            }
        } catch {
            podcastFetcherLogger.error("Error fetching episodes: \(error, privacy: .public)")
        }
    }
    
    func fetchEpisodesDirect(for podcast: Podcast) async -> (episodes: [PodcastEpisode], feedArtwork: URL?) {
        guard let feedUrlString = podcast.feedUrl,
              let sanitizedFeedURL = MediaURLSanitizer.sanitize(feedUrlString) else {
            return ([], nil)
        }

        let cacheKey = sanitizedFeedURL.absoluteString

        guard shouldAttemptNetwork(for: sanitizedFeedURL) else {
            podcastFetcherLogger.warning("Skipping direct episode fetch for unresolved host: \(feedUrlString, privacy: .private)")
            return ([], nil)
        }

        if let cached = episodeCache[cacheKey] ?? episodeCache[feedUrlString] {
            return (Array(cached.episodes.prefix(maxEpisodesPerFeed)), cached.feedArtwork)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: sanitizedFeedURL)

            let parser = FeedKitRSSParser(feedUrl: cacheKey)
            let (allEpisodes, feedArt, channelTitle) = parser.parse(data: data)

            let limitedEpisodes = Array(allEpisodes.prefix(maxEpisodesPerFeed))

            if let channelTitle = channelTitle, !channelTitle.isEmpty {
                podcast.title = channelTitle
            }

            episodeCache[cacheKey] = (limitedEpisodes, feedArt)
            if episodeCache.count > maxEpisodeCacheSize {
                let overflow = episodeCache.count - maxEpisodeCacheSize
                let keysToRemove = Array(episodeCache.keys.prefix(overflow))
                for key in keysToRemove {
                    episodeCache.removeValue(forKey: key)
                }
            }

            return (limitedEpisodes, feedArt)
        } catch {
            podcastFetcherLogger.error("Direct episode fetch failed: \(error, privacy: .public)")
            return ([], nil)
        }
    }
    
    func fetchChannelInfoDirect(for podcast: Podcast) async -> (channelTitle: String?, feedArtwork: URL?) {
        guard let feedUrlString = podcast.feedUrl,
              let sanitizedFeedURL = MediaURLSanitizer.sanitize(feedUrlString) else {
            return (nil, nil)
        }

        let cacheKey = sanitizedFeedURL.absoluteString

        guard shouldAttemptNetwork(for: sanitizedFeedURL) else {
            podcastFetcherLogger.warning("Skipping channel info fetch for unresolved host: \(feedUrlString, privacy: .private)")
            return (nil, nil)
        }

        if let cached = episodeCache[cacheKey] ?? episodeCache[feedUrlString] {
            return (podcast.title, cached.feedArtwork)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: sanitizedFeedURL)

            let parser = FeedKitRSSParser(feedUrl: cacheKey)
            let (_, feedArt, channelTitle) = parser.parse(data: data)

            episodeCache[cacheKey] = ([], feedArt)
            if episodeCache.count > maxEpisodeCacheSize {
                let overflow = episodeCache.count - maxEpisodeCacheSize
                let keysToRemove = Array(episodeCache.keys.prefix(overflow))
                for key in keysToRemove {
                    episodeCache.removeValue(forKey: key)
                }
            }

            return (channelTitle, feedArt)
        } catch {
            podcastFetcherLogger.error("Channel info fetch failed: \(error, privacy: .public)")
            return (nil, nil)
        }
    }
    
    /// Clears all caches to free memory
    func clearCaches() {
        searchCache.removeAll()
        episodeCache.removeAll()
        podcastFetcherLogger.info("PodcastFetcher caches cleared for memory optimization")
    }

    private func shouldAttemptNetwork(for url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        if host == "localhost" { return true }

        if host.contains(".") {
            return true
        }

        if host.contains(":") { // IPv6
            return true
        }

        let ipv4CharacterSet = CharacterSet(charactersIn: "0123456789.")
        if host.unicodeScalars.allSatisfy({ ipv4CharacterSet.contains($0) }) {
            return true
        }

        return false
    }
}

class RSSParser: NSObject, XMLParserDelegate {
    private var episodes: [PodcastEpisode] = []
    private var channelTitle: String?
    private var currentElement = ""
    private var currentTitle = ""
    private var currentAudioURL = ""
    private var currentArtworkURL: String?
    private var currentDuration: Double?
    private var currentDescription = ""
    private let feedUrl: String
    
    private var insideItem = false
    private var insideChannel = false
    private var insideImage = false
    private var feedArtworkURL: String?
    
    init(feedUrl: String) {
        self.feedUrl = feedUrl
        super.init()
    }
    
    func parse(data: Data) -> (episodes: [PodcastEpisode], feedArtwork: URL?, channelTitle: String?) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        let feedURL = feedArtworkURL.flatMap { MediaURLSanitizer.sanitize($0) }
        // Return only the first 10 episodes
        let limitedEpisodes = Array(episodes.prefix(10))
        return (limitedEpisodes, feedURL, channelTitle)
    }
    
    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        // Also check for itunes:duration specifically
        if elementName == "duration" && namespaceURI == "http://www.itunes.com/dtds/podcast-1.0.dtd" {
            currentElement = "itunes:duration"
        }
        
        if elementName == "channel" {
            insideChannel = true
        }
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentAudioURL = ""
            currentArtworkURL = nil
            currentDuration = nil
            currentDescription = ""
        }
        if insideItem && elementName == "enclosure", let urlString = attributeDict["url"] {
            currentAudioURL = urlString
        }
        if insideItem && elementName == "itunes:image", let href = attributeDict["href"] {
            currentArtworkURL = href
        }
        if insideChannel && elementName == "itunes:image", let href = attributeDict["href"] {
            feedArtworkURL = href
        }
        if insideChannel && elementName == "image" {
            insideImage = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if insideChannel && !insideItem && currentElement == "title" {
            if !trimmed.isEmpty {
                channelTitle = (channelTitle ?? "") + trimmed
            }
        }
        if insideItem && currentElement == "title" {
            currentTitle += string
        }
        if insideItem && currentElement == "itunes:duration" {
            if trimmed.isEmpty {
                currentDuration = 0.0
            } else {
                currentDuration = parseDuration(trimmed)
            }
        }
        if insideImage && currentElement == "url" {
            if !trimmed.isEmpty {
                feedArtworkURL = trimmed
            }
        }
        if insideItem && currentElement == "description" {
            currentDescription += string
        }
    }
    
    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        // Removed debug logging for XML parsing performance.
        
        // Reset currentElement when we're done with it
        if currentElement == elementName {
            currentElement = ""
        }
        
        if elementName == "item" {
            if let audioURL = MediaURLSanitizer.sanitize(currentAudioURL) {
                let artworkURL = currentArtworkURL.flatMap { MediaURLSanitizer.sanitize($0) }
                let showNotes = currentDescription.htmlStripped
                
                // Create episode
                let ep = PodcastEpisode(
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    url: audioURL,
                    artworkURL: artworkURL,
                    duration: currentDuration,
                    showNotes: showNotes.isEmpty ? nil : showNotes,
                    feedUrl: feedUrl
                )
                
                // Add the episode to our array
                episodes.append(ep)
                
                
                // Episode created.
            }
            insideItem = false
        }
        if elementName == "channel" {
            insideChannel = false
        }
        if elementName == "image" {
            insideImage = false
        }
    }
    
    /// Fetches the duration of an audio file by loading its metadata
    private func fetchDurationFromAudio(url: URL) async throws -> Double? {
        // Skip for non-HTTP URLs
        guard url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        
        // Create an asset and load its duration
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        
        // Return the duration if it's valid
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        podcastFetcherLogger.error("RSS Parser error: \(parseError, privacy: .public)")
    }
    
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
