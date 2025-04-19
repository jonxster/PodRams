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
#if canImport(FeedKit)
import FeedKit
#endif

class PodcastFetcher: ObservableObject, @unchecked Sendable {
    @Published var searchQuery = ""
    @Published var podcasts: [Podcast] = []
    
    private var searchCache: [String: [Podcast]] = [:]
    private var episodeCache: [String: (episodes: [PodcastEpisode], feedArtwork: URL?)] = [:]
    private let cacheQueue = DispatchQueue(label: "com.podcasts.fetcher.cache", attributes: .concurrent)
    
    func searchPodcasts() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        var cached: [Podcast]?
        cacheQueue.sync { cached = self.searchCache[query] }
        if let cached = cached {
            DispatchQueue.main.async { self.podcasts = cached }
            return
        }
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=podcast&term=\(encodedQuery)&entity=podcast") else {
            print("Invalid search query")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let response = try decoder.decode(PodcastSearchResponse.self, from: data)
            
            let results = response.results.compactMap { result -> Podcast? in
                guard let feedUrl = result.feedUrl, URL(string: feedUrl) != nil else { return nil }
                let p = Podcast(title: result.collectionName, feedUrl: feedUrl)
                if let art = result.artworkUrl600, let artURL = URL(string: art) {
                    p.feedArtworkURL = artURL
                }
                return p
            }
            
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.searchCache[query] = results
                if self.searchCache.count > 50 { self.searchCache.removeValue(forKey: self.searchCache.keys.first!) }
            }
            
            DispatchQueue.main.async { self.podcasts = results }
        } catch {
            print("Error fetching podcasts: \(error)")
        }
    }
    
    func fetchEpisodes(for podcast: Podcast) async {
        guard let feedUrlString = podcast.feedUrl, let feedUrl = URL(string: feedUrlString) else {
            print("Invalid feed URL")
            return
        }
        
        var cached: (episodes: [PodcastEpisode], feedArtwork: URL?)?
        cacheQueue.sync { cached = self.episodeCache[feedUrlString] }
        if let cached = cached {
            DispatchQueue.main.async {
                podcast.episodes = cached.episodes
                if let feedArt = cached.feedArtwork { podcast.feedArtworkURL = feedArt }
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: feedUrl)
            
            #if canImport(FeedKit)
            // Try FeedKitRSSParser first
            let parser = FeedKitRSSParser(feedUrl: feedUrlString)
            let (eps, fArt, chTitle) = parser.parse(data: data)
            
            // If no episodes were returned, try the legacy parser as fallback
            if eps.isEmpty {
                print("FeedKit parser returned no episodes, trying legacy parser")
                let legacyParser = RSSParser(feedUrl: feedUrlString)
                let (legacyEps, legacyArt, legacyTitle) = legacyParser.parse(data: data)
                
                // If legacy parser found episodes, use those
                if !legacyEps.isEmpty {
                    cacheQueue.async(flags: .barrier) { [weak self] in
                        guard let self = self else { return }
                        self.episodeCache[feedUrlString] = (legacyEps, legacyArt)
                        if self.episodeCache.count > 20 { self.episodeCache.removeValue(forKey: self.episodeCache.keys.first!) }
                    }
                    
                    DispatchQueue.main.async {
                        podcast.episodes = legacyEps
                        if let feedArt = legacyArt { podcast.feedArtworkURL = feedArt }
                        if let chTitle = legacyTitle, !chTitle.isEmpty { podcast.title = chTitle }
                    }
                    return
                }
            }
            #else
            // If FeedKit is not available, use the legacy parser directly
            let parser = RSSParser(feedUrl: feedUrlString)
            let (eps, fArt, chTitle) = parser.parse(data: data)
            #endif
            
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.episodeCache[feedUrlString] = (eps, fArt)
                if self.episodeCache.count > 20 { self.episodeCache.removeValue(forKey: self.episodeCache.keys.first!) }
            }
            
            DispatchQueue.main.async {
                podcast.episodes = eps
                if let feedArt = fArt { podcast.feedArtworkURL = feedArt }
                if let chTitle = chTitle, !chTitle.isEmpty { podcast.title = chTitle }
            }
        } catch {
            print("Error fetching episodes: \(error)")
        }
    }
    
    func fetchEpisodesDirect(for podcast: Podcast) async -> (episodes: [PodcastEpisode], feedArtwork: URL?) {
        guard let feedUrlString = podcast.feedUrl, let feedUrl = URL(string: feedUrlString) else {
            return ([], nil)
        }
        
        var cached: (episodes: [PodcastEpisode], feedArtwork: URL?)?
        cacheQueue.sync { cached = self.episodeCache[feedUrlString] }
        if let cached = cached {
            return cached
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: feedUrl)
            
            #if canImport(FeedKit)
            // Try FeedKitRSSParser first
            let parser = FeedKitRSSParser(feedUrl: feedUrlString)
            let (eps, fArt, chTitle) = parser.parse(data: data)
            
            // If no episodes were returned, try the legacy parser as fallback
            if eps.isEmpty {
                print("FeedKit parser returned no episodes, trying legacy parser")
                let legacyParser = RSSParser(feedUrl: feedUrlString)
                let (legacyEps, legacyArt, legacyTitle) = legacyParser.parse(data: data)
                
                // If legacy parser found episodes, use those
                if !legacyEps.isEmpty {
                    if let chTitle = legacyTitle, !chTitle.isEmpty { podcast.title = chTitle }
                    
                    cacheQueue.async(flags: .barrier) { [weak self] in
                        guard let self = self else { return }
                        self.episodeCache[feedUrlString] = (legacyEps, legacyArt)
                        if self.episodeCache.count > 20 { self.episodeCache.removeValue(forKey: self.episodeCache.keys.first!) }
                    }
                    
                    return (legacyEps, legacyArt)
                }
            }
            #else
            // If FeedKit is not available, use the legacy parser directly
            let parser = RSSParser(feedUrl: feedUrlString)
            let (eps, fArt, chTitle) = parser.parse(data: data)
            #endif
            
            if let chTitle = chTitle, !chTitle.isEmpty { podcast.title = chTitle }
            
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.episodeCache[feedUrlString] = (eps, fArt)
                if self.episodeCache.count > 20 { self.episodeCache.removeValue(forKey: self.episodeCache.keys.first!) }
            }
            
            return (eps, fArt)
        } catch {
            print("Error: \(error)")
            return ([], nil)
        }
    }
    
    func fetchChannelInfoDirect(for podcast: Podcast) async -> (channelTitle: String?, feedArtwork: URL?) {
        guard let feedUrlString = podcast.feedUrl, let feedUrl = URL(string: feedUrlString) else {
            return (nil, nil)
        }
        
        var cached: (episodes: [PodcastEpisode], feedArtwork: URL?)?
        cacheQueue.sync { cached = self.episodeCache[feedUrlString] }
        if let cached = cached {
            return (podcast.title, cached.feedArtwork)
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: feedUrl)
            
            #if canImport(FeedKit)
            // Try FeedKitRSSParser first
            let parser = FeedKitRSSParser(feedUrl: feedUrlString)
            let (_, fArt, chTitle) = parser.parse(data: data)
            
            // If no title was returned, try the legacy parser as fallback
            if chTitle == nil {
                print("FeedKit parser returned no channel title, trying legacy parser")
                let legacyParser = RSSParser(feedUrl: feedUrlString)
                let (_, legacyArt, legacyTitle) = legacyParser.parse(data: data)
                return (legacyTitle, legacyArt)
            }
            #else
            // If FeedKit is not available, use the legacy parser directly
            let parser = RSSParser(feedUrl: feedUrlString)
            let (_, fArt, chTitle) = parser.parse(data: data)
            #endif
            
            return (chTitle, fArt)
        } catch {
            print("Error: \(error)")
            return (nil, nil)
        }
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
        let feedURL = feedArtworkURL.flatMap { URL(string: $0) }
        return (episodes, feedURL, channelTitle)
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
            if let audioURL = URL(string: currentAudioURL) {
                let artworkURL = currentArtworkURL.flatMap { URL(string: $0) }
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
        print("RSS Parser error: \(parseError)")
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
