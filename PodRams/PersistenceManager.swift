import Foundation

fileprivate enum PersistenceKeys: String {
    case favorites = "favorites.json"
    case cue = "cue.json"
    case lastPlayback = "lastPlayback.json"
    case subscriptions = "subscriptions.json" // New key for subscriptions
    case downloads = "downloads.json" // New key for downloads
}

struct PersistedEpisode: Codable, Equatable {
    let feedUrl: String
    let title: String
    let audioURL: String
    let duration: Double?
    let podcastName: String?
    
    var isValid: Bool {
        !feedUrl.isEmpty && !title.isEmpty && !audioURL.isEmpty && URL(string: audioURL) != nil
    }
}

struct PersistedPodcast: Codable {
    let title: String
    let feedUrl: String
    let feedArtworkURL: String?
}

struct PersistedDownload: Codable {
    let episodeUrl: String
    let localFilePath: String
}

struct PersistenceManager {
    private static let fileManager = FileManager.default
    private static let documentsDirectory: URL = {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let queue = DispatchQueue(label: "com.podcasts.persistence", qos: .utility)
    
    private static var favoritesCache: [Podcast]?
    private static var cueCache: [PodcastEpisode]?
    private static var lastPlaybackCache: PodcastEpisode?
    private static var subscriptionsCache: [Podcast]? // New cache
    private static var downloadsCache: [PersistedDownload]?
    
    private static func fileURL(for key: PersistenceKeys) -> URL {
        documentsDirectory.appendingPathComponent(key.rawValue)
    }
    
    private static func saveData<T: Encodable>(_ data: T, to key: PersistenceKeys) {
        print("PersistenceManager: saveData called for key: \(key.rawValue)")
        
        queue.async {
            do {
                let encoded = try encoder.encode(data)
                let url = fileURL(for: key)
                print("PersistenceManager: Saving data to \(url.path)")
                try encoded.write(to: url, options: [.atomic])
                print("PersistenceManager: Successfully saved data to \(key.rawValue)")
            } catch {
                print("Error saving \(key.rawValue): \(error)")
            }
        }
    }
    
    private static func loadData<T: Decodable>(from key: PersistenceKeys) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async {
                let url = fileURL(for: key)
                do {
                    let data = try Data(contentsOf: url)
                    let result = try JSONDecoder().decode(T.self, from: data)
                    DispatchQueue.main.async {
                        continuation.resume(returning: result)
                    }
                } catch {
                    // File missing or decoding error
                    print("Error loading \(key.rawValue): \(error)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
    // Favorites
    static func saveFavorites(_ favorites: [Podcast]) {
        let persisted = favorites.compactMap { podcast -> PersistedPodcast? in
            guard let feedUrl = podcast.feedUrl, !feedUrl.isEmpty, URL(string: feedUrl) != nil else {
                print("Warning: Skipping podcast with invalid feed URL: \(podcast.title)")
                return nil
            }
            return PersistedPodcast(
                title: podcast.title,
                feedUrl: feedUrl,
                feedArtworkURL: podcast.feedArtworkURL?.absoluteString
            )
        }
        favoritesCache = favorites
        saveData(persisted, to: .favorites)
    }
    
    static func loadFavorites() async -> [Podcast] {
        if let cached = favoritesCache { return cached }
        let persisted: [PersistedPodcast]? = await loadData(from: .favorites)
        let result = (persisted ?? []).compactMap { p -> Podcast? in
            guard !p.feedUrl.isEmpty, URL(string: p.feedUrl) != nil else {
                print("Warning: Invalid feed URL found in favorites: \(p.feedUrl)")
                return nil
            }
            let podcast = Podcast(title: p.title, feedUrl: p.feedUrl)
            if let artStr = p.feedArtworkURL, let artURL = URL(string: artStr) {
                podcast.feedArtworkURL = artURL
            }
            return podcast
        }
        favoritesCache = result
        return result
    }
    
    // Cue
    static func saveCue(_ episodes: [PodcastEpisode], feedUrl: String?) {
        print("PersistenceManager: saveCue called with \(episodes.count) episodes and feedUrl: \(feedUrl ?? "nil")")
        
        // Check if we have a valid feedUrl
        let validFeedUrl = feedUrl ?? episodes.first?.feedUrl ?? ""
        
        // Only proceed if we have a valid feedUrl or at least one episode with a feedUrl
        guard !validFeedUrl.isEmpty || episodes.contains(where: { $0.feedUrl != nil && !$0.feedUrl!.isEmpty }) else {
            print("Warning: Cannot save cue without a valid feedUrl")
            queue.async { try? fileManager.removeItem(at: fileURL(for: .cue)) }
            cueCache = nil
            return
        }
        
        // Use the first valid feedUrl we can find if the provided one is empty
        let effectiveFeedUrl = !validFeedUrl.isEmpty ? validFeedUrl : 
                              (episodes.first(where: { $0.feedUrl != nil && !$0.feedUrl!.isEmpty })?.feedUrl ?? "")
        
        print("PersistenceManager: Saving cue with \(episodes.count) episodes using feedUrl: \(effectiveFeedUrl)")
        
        if !episodes.isEmpty {
            print("PersistenceManager: First episode in cue: \(episodes[0].title), URL: \(episodes[0].url.absoluteString)")
        }
        
        let persistedEpisodes = episodes.compactMap { episode -> PersistedEpisode? in
            let urlString = episode.url.absoluteString
            guard !urlString.isEmpty else {
                print("Warning: Skipping episode with invalid URL: \(episode.title)")
                return nil
            }
            
            print("PersistenceManager: Persisting episode: \(episode.title), URL: \(urlString)")
            
            return PersistedEpisode(
                feedUrl: effectiveFeedUrl,
                title: episode.title,
                audioURL: urlString,
                duration: episode.duration,
                podcastName: episode.podcastName
            )
        }
        
        print("PersistenceManager: Created \(persistedEpisodes.count) persisted episodes")
        
        // Update the cache before saving to disk
        cueCache = episodes
        
        // Save to disk
        saveData(persistedEpisodes, to: .cue)
        
        // Post a notification that the cue has been updated
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
            print("PersistenceManager: Posted CueUpdated notification")
        }
    }
    
    static func loadCue() async -> [PodcastEpisode] {
        // Return cached cue if available and not empty
        if let cached = cueCache, !cached.isEmpty { 
            print("PersistenceManager: Returning cached cue with \(cached.count) episodes")
            return cached 
        }
        
        // Load from disk
        let persisted: [PersistedEpisode]? = await loadData(from: .cue)
        
        // Process the loaded data
        let result = persisted?.compactMap { pe -> PodcastEpisode? in
            guard pe.isValid, let url = URL(string: pe.audioURL) else {
                print("Warning: Invalid persisted episode: \(pe.title)")
                return nil
            }
            return PodcastEpisode(
                title: pe.title,
                url: url,
                artworkURL: nil,
                duration: pe.duration,
                showNotes: nil,
                feedUrl: pe.feedUrl,
                podcastName: pe.podcastName
            )
        } ?? []
        
        print("PersistenceManager: Loaded cue from disk with \(result.count) episodes")
        
        // Update the cache
        cueCache = result
        return result
    }
    
    // Last Playback
    static func saveLastPlayback(episode: PodcastEpisode?, feedUrl: String?) {
        guard let episode = episode, let feedUrl = feedUrl, !feedUrl.isEmpty,
              !episode.url.absoluteString.isEmpty else {
            queue.async { try? fileManager.removeItem(at: fileURL(for: .lastPlayback)) }
            lastPlaybackCache = nil
            return
        }
        
        let persisted = PersistedEpisode(
            feedUrl: feedUrl,
            title: episode.title,
            audioURL: episode.url.absoluteString,
            duration: episode.duration,
            podcastName: episode.podcastName
        )
        lastPlaybackCache = episode
        saveData(persisted, to: .lastPlayback)
    }
    
    static func loadLastPlayback() async -> PodcastEpisode? {
        if let cached = lastPlaybackCache { return cached }
        let pe: PersistedEpisode? = await loadData(from: .lastPlayback)
        if let pe = pe, pe.isValid, let url = URL(string: pe.audioURL) {
            let episode = PodcastEpisode(
                title: pe.title,
                url: url,
                artworkURL: nil,
                duration: pe.duration,
                showNotes: nil,
                feedUrl: pe.feedUrl,
                podcastName: pe.podcastName
            )
            lastPlaybackCache = episode
            return episode
        }
        return nil
    }
    
    // Subscriptions
    static func saveSubscriptions(_ subscriptions: [Podcast]) {
        let persisted = subscriptions.compactMap { podcast -> PersistedPodcast? in
            guard let feedUrl = podcast.feedUrl, !feedUrl.isEmpty, URL(string: feedUrl) != nil else {
                print("Warning: Skipping podcast with invalid feed URL: \(podcast.title)")
                return nil
            }
            return PersistedPodcast(
                title: podcast.title,
                feedUrl: feedUrl,
                feedArtworkURL: podcast.feedArtworkURL?.absoluteString
            )
        }
        subscriptionsCache = subscriptions
        saveData(persisted, to: .subscriptions)
    }
    
    static func loadSubscriptions() async -> [Podcast] {
        if let cached = subscriptionsCache { return cached }
        let persisted: [PersistedPodcast]? = await loadData(from: .subscriptions)
        let result = (persisted ?? []).compactMap { p -> Podcast? in
            guard !p.feedUrl.isEmpty, URL(string: p.feedUrl) != nil else {
                print("Warning: Invalid feed URL found in subscriptions: \(p.feedUrl)")
                return nil
            }
            let podcast = Podcast(title: p.title, feedUrl: p.feedUrl)
            if let artStr = p.feedArtworkURL, let artURL = URL(string: artStr) {
                podcast.feedArtworkURL = artURL
            }
            return podcast
        }
        subscriptionsCache = result
        return result
    }
    
    /// Synchronous version of loadSubscriptions that doesn't use async/await
    /// This is used in places where async/await cannot be used
    static func loadSubscriptionsSync() -> [Podcast] {
        // Return cached subscriptions if available
        if let cached = subscriptionsCache { return cached }
        
        // Try to load from file synchronously
        let url = fileURL(for: .subscriptions)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let persisted = try decoder.decode([PersistedPodcast].self, from: data)
            
            let result = persisted.compactMap { p -> Podcast? in
                guard !p.feedUrl.isEmpty, URL(string: p.feedUrl) != nil else {
                    print("Warning: Invalid feed URL found in subscriptions: \(p.feedUrl)")
                    return nil
                }
                let podcast = Podcast(title: p.title, feedUrl: p.feedUrl)
                if let artStr = p.feedArtworkURL, let artURL = URL(string: artStr) {
                    podcast.feedArtworkURL = artURL
                }
                return podcast
            }
            
            // Update the cache
            subscriptionsCache = result
            return result
        } catch {
            print("Error loading subscriptions synchronously: \(error)")
            return []
        }
    }
    
    // Downloads
    static func saveDownloads(_ downloads: [PersistedDownload]) {
        downloadsCache = downloads
        saveData(downloads, to: .downloads)
    }
    
    static func loadDownloads() async -> [PersistedDownload] {
        if let cached = downloadsCache { return cached }
        let persisted: [PersistedDownload]? = await loadData(from: .downloads)
        let result = persisted ?? []
        downloadsCache = result
        return result
    }
    
    /// Clears the cue cache, forcing a reload from disk on next access
    static func clearCueCache() {
        cueCache = nil
    }
    
    /// Clears the favorites cache, forcing a reload from disk on next access
    static func clearFavoritesCache() {
        favoritesCache = nil
    }
    
    /// Clears the subscriptions cache, forcing a reload from disk on next access
    static func clearSubscriptionsCache() {
        subscriptionsCache = nil
    }
    
    /// Clears the last playback cache, forcing a reload from disk on next access
    static func clearLastPlaybackCache() {
        lastPlaybackCache = nil
    }
    
    /// Clears the downloads cache, forcing a reload from disk on next access
    static func clearDownloadsCache() {
        downloadsCache = nil
    }
    
    /// Optimizes memory usage by clearing all caches
    static func optimizeMemoryUsage() {
        print("PersistenceManager: Optimizing memory usage by clearing caches")
        clearCueCache()
        clearFavoritesCache()
        clearSubscriptionsCache() 
        clearLastPlaybackCache()
        clearDownloadsCache()
    }
    
    /// Sets up memory optimization notifications
    static func setupMemoryOptimization() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OptimizePersistentCache"),
            object: nil,
            queue: .main
        ) { _ in
            optimizeMemoryUsage()
        }
    }
    
    /// Clears all persisted data, synchronously removing files and resetting caches.
    static func clearAll() {
        let keys: [PersistenceKeys] = [.favorites, .cue, .lastPlayback, .subscriptions, .downloads]
        // Perform removal synchronously to ensure files are deleted before returning
        queue.sync {
            for key in keys {
                try? fileManager.removeItem(at: fileURL(for: key))
            }
            favoritesCache = nil
            cueCache = nil
            lastPlaybackCache = nil
            subscriptionsCache = nil
            downloadsCache = nil
        }
    }
    
    static var hasData: Bool {
        if favoritesCache != nil || cueCache != nil || lastPlaybackCache != nil { return true }
        let keys: [PersistenceKeys] = [.favorites, .cue, .lastPlayback]
        return keys.contains { fileManager.fileExists(atPath: fileURL(for: $0).path) }
    }
    
    /// Loads a single podcast by feed URL
    /// - Parameter feedUrl: The feed URL of the podcast to load
    /// - Returns: The podcast if found, nil otherwise
    static func loadPodcast(feedUrl: String?) -> Podcast? {
        guard let feedUrl = feedUrl, !feedUrl.isEmpty else {
            return nil
        }
        
        let podcasts = loadSubscriptionsSync()
        return podcasts.first(where: { $0.feedUrl == feedUrl })
    }
}
