import Foundation

fileprivate enum PersistenceKeys: String {
    case favorites = "favorites.json"
    case cue = "cue.json"
    case lastPlayback = "lastPlayback.json"
    case subscriptions = "subscriptions.json" // New key for subscriptions
    case downloads = "downloads.json" // New key for downloads
    case playbackProgress = "playbackProgress.json"
}

struct PersistedEpisode: Codable, Equatable, Sendable {
    let feedUrl: String
    let title: String
    let audioURL: String
    let duration: Double?
    let podcastName: String?
    
    var isValid: Bool {
        !feedUrl.isEmpty && !title.isEmpty && !audioURL.isEmpty && URL(string: audioURL) != nil
    }
}

struct PersistedPodcast: Codable, Sendable {
    let title: String
    let feedUrl: String
    let feedArtworkURL: String?
}

struct PersistedDownload: Codable, Sendable {
    let episodeUrl: String
    let localFilePath: String
}

struct PersistedPlaybackProgress: Codable, Sendable {
    let episodeId: String
    let audioURL: String
    let position: Double
    let duration: Double?
    let updatedAt: Date
}

private final class PersistenceState: @unchecked Sendable {
    let fileManager = FileManager.default
    lazy var documentsDirectory: URL = {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    let queue = DispatchQueue(label: "com.podcasts.persistence", qos: .utility)
    
    var favoritesCache: [Podcast]?
    var cueCache: [PodcastEpisode]?
    var lastPlaybackCache: PodcastEpisode?
    var subscriptionsCache: [Podcast]?
    var downloadsCache: [PersistedDownload]?
    var playbackProgressCache: [String: PersistedPlaybackProgress]?
}

struct PersistenceManager {
    private static let state = PersistenceState()
    
    private static func fileURL(for key: PersistenceKeys) -> URL {
        state.documentsDirectory.appendingPathComponent(key.rawValue)
    }
    
    private static func saveData<T: Encodable & Sendable>(_ data: T, to key: PersistenceKeys) {
        print("PersistenceManager: saveData called for key: \(key.rawValue)")
        
        state.queue.async {
            do {
                let encoder = JSONEncoder()
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
    
    private static func loadData<T: Decodable & Sendable>(from key: PersistenceKeys) async -> T? {
        await withCheckedContinuation { continuation in
            state.queue.async {
                let url = fileURL(for: key)
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    let result = try decoder.decode(T.self, from: data)
                    continuation.resume(returning: result)
                } catch {
                    // File missing or decoding error
                    print("Error loading \(key.rawValue): \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // Favorites
    @MainActor
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
        state.favoritesCache = favorites
        saveData(persisted, to: .favorites)
    }
    
    @MainActor
    static func loadFavorites() async -> [Podcast] {
        if let cached = state.favoritesCache { return cached }
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
        state.favoritesCache = result
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
            state.queue.async { try? state.fileManager.removeItem(at: fileURL(for: .cue)) }
            state.cueCache = nil
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
        state.cueCache = episodes
        
        // Save to disk
        saveData(persistedEpisodes, to: .cue)
        
        // Post a notification that the cue has been updated
        Task { @MainActor in
            NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
            print("PersistenceManager: Posted CueUpdated notification")
        }
    }
    
    static func loadCue() async -> [PodcastEpisode] {
        // Return cached cue if available and not empty
        if let cached = state.cueCache, !cached.isEmpty { 
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
        state.cueCache = result
        return result
    }
    
    // Last Playback
    static func saveLastPlayback(episode: PodcastEpisode?, feedUrl: String?) {
        guard let episode = episode, let feedUrl = feedUrl, !feedUrl.isEmpty,
              !episode.url.absoluteString.isEmpty else {
            state.queue.async { try? state.fileManager.removeItem(at: fileURL(for: .lastPlayback)) }
            state.lastPlaybackCache = nil
            return
        }
        
        let persisted = PersistedEpisode(
            feedUrl: feedUrl,
            title: episode.title,
            audioURL: episode.url.absoluteString,
            duration: episode.duration,
            podcastName: episode.podcastName
        )
        state.lastPlaybackCache = episode
        saveData(persisted, to: .lastPlayback)
    }
    
    static func loadLastPlayback() async -> PodcastEpisode? {
        if let cached = state.lastPlaybackCache { return cached }
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
            state.lastPlaybackCache = episode
            return episode
        }
        return nil
    }
    
    // Subscriptions
    @MainActor
    static func saveSubscriptions(_ subscriptions: [Podcast]) {
        let persisted = subscriptions.compactMap { podcast -> PersistedPodcast? in
            guard let feedUrl = podcast.feedUrl, !feedUrl.isEmpty, URL(string: feedUrl) != nil else {
                print("Warning: Skipping podcast with invalid feed URL: \(podcast.title)")
                return nil
            }
            guard isLikelyReachableFeedURL(feedUrl) else {
                print("Warning: Skipping podcast with unreachable host: \(feedUrl)")
                return nil
            }
            return PersistedPodcast(
                title: podcast.title,
                feedUrl: feedUrl,
                feedArtworkURL: podcast.feedArtworkURL?.absoluteString
            )
        }
        state.subscriptionsCache = subscriptions
        saveData(persisted, to: .subscriptions)
    }
    
    @MainActor
    static func loadSubscriptions() async -> [Podcast] {
        if let cached = state.subscriptionsCache { return cached }
        let persisted: [PersistedPodcast]? = await loadData(from: .subscriptions)
        let filtered = (persisted ?? []).filter { candidate in
            guard !candidate.feedUrl.isEmpty, URL(string: candidate.feedUrl) != nil else {
                print("Warning: Invalid feed URL found in subscriptions: \(candidate.feedUrl)")
                return false
            }
            guard isLikelyReachableFeedURL(candidate.feedUrl) else {
                print("Warning: Removing unreachable subscription host: \(candidate.feedUrl)")
                return false
            }
            return true
        }

        let result = filtered.compactMap { p -> Podcast? in
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

        state.subscriptionsCache = result

        if let original = persisted, original.count != filtered.count {
            Task { @MainActor in saveSubscriptions(result) }
        }

        return result
    }
    
    /// Synchronous version of loadSubscriptions that doesn't use async/await
    /// This is used in places where async/await cannot be used
    @MainActor
    static func loadSubscriptionsSync() -> [Podcast] {
        // Return cached subscriptions if available
        if let cached = state.subscriptionsCache { return cached }
        
        // Try to load from file synchronously
        let url = fileURL(for: .subscriptions)
        guard state.fileManager.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let persisted = try decoder.decode([PersistedPodcast].self, from: data)
            
            let filtered = persisted.filter { candidate in
                guard !candidate.feedUrl.isEmpty, URL(string: candidate.feedUrl) != nil else {
                    print("Warning: Invalid feed URL found in subscriptions: \(candidate.feedUrl)")
                    return false
                }
                guard isLikelyReachableFeedURL(candidate.feedUrl) else {
                    print("Warning: Removing unreachable subscription host: \(candidate.feedUrl)")
                    return false
                }
                return true
            }

            let result = filtered.compactMap { p -> Podcast? in
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
            
            state.subscriptionsCache = result

            if persisted.count != filtered.count {
                Task { @MainActor in saveSubscriptions(result) }
            }

            return result
        } catch {
            print("Error loading subscriptions synchronously: \(error)")
            return []
        }
    }

    private static func isLikelyReachableFeedURL(_ urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString),
              let host = components.host, !host.isEmpty else { return false }

        if host == "localhost" || host == "127.0.0.1" { return true }
        if host.contains(".") || host.contains(":") { return true }

        let ipv4CharacterSet = CharacterSet(charactersIn: "0123456789.")
        if host.unicodeScalars.allSatisfy({ ipv4CharacterSet.contains($0) }) {
            return true
        }

        return false
    }
    
    // Downloads
    static func saveDownloads(_ downloads: [PersistedDownload]) {
        state.downloadsCache = downloads
        saveData(downloads, to: .downloads)
    }
    
    static func loadDownloads() async -> [PersistedDownload] {
        if let cached = state.downloadsCache { return cached }
        let persisted: [PersistedDownload]? = await loadData(from: .downloads)
        let result = persisted ?? []
        state.downloadsCache = result
        return result
    }

    // Playback progress
    private static func ensurePlaybackProgressCacheLoadedLocked() -> [String: PersistedPlaybackProgress] {
        if let cache = state.playbackProgressCache { return cache }
        let url = fileURL(for: .playbackProgress)
        guard state.fileManager.fileExists(atPath: url.path) else {
            state.playbackProgressCache = [:]
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let cache = try decoder.decode([String: PersistedPlaybackProgress].self, from: data)
            state.playbackProgressCache = cache
            return cache
        } catch {
            print("Error loading playback progress: \(error)")
            state.playbackProgressCache = [:]
            return [:]
        }
    }

    static func playbackProgress(for episode: PodcastEpisode) -> PersistedPlaybackProgress? {
        state.queue.sync {
            let cache = ensurePlaybackProgressCacheLoadedLocked()
            if let entry = cache[episode.id] { return entry }
            return cache.first { $0.value.audioURL == episode.url.absoluteString }?.value
        }
    }

    static func playbackProgress(forURL url: URL) -> PersistedPlaybackProgress? {
        state.queue.sync {
            let cache = ensurePlaybackProgressCacheLoadedLocked()
            return cache.first { $0.value.audioURL == url.absoluteString }?.value
        }
    }

    static func allPlaybackProgress() -> [String: PersistedPlaybackProgress] {
        state.queue.sync {
            ensurePlaybackProgressCacheLoadedLocked()
        }
    }

    static func updatePlaybackProgress(for episode: PodcastEpisode, position: Double, duration: Double?) {
        guard position.isFinite, position >= 0 else { return }
        let sanitizedPosition = max(0, position)
        let entry = PersistedPlaybackProgress(
            episodeId: episode.id,
            audioURL: episode.url.absoluteString,
            position: sanitizedPosition,
            duration: duration,
            updatedAt: Date()
        )
        state.queue.async {
            var cache = ensurePlaybackProgressCacheLoadedLocked()
            cache = cache.filter { $0.value.audioURL != entry.audioURL || $0.key == episode.id }
            cache[episode.id] = entry
            state.playbackProgressCache = cache
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(cache)
                try data.write(to: fileURL(for: .playbackProgress), options: [.atomic])
            } catch {
                print("Error saving playback progress: \(error)")
            }
        }
    }

    static func clearPlaybackProgress(for episode: PodcastEpisode) {
        state.queue.async {
            var cache = ensurePlaybackProgressCacheLoadedLocked()
            cache.removeValue(forKey: episode.id)
            cache = cache.filter { $0.value.audioURL != episode.url.absoluteString }
            state.playbackProgressCache = cache
            let url = fileURL(for: .playbackProgress)
            if cache.isEmpty {
                try? state.fileManager.removeItem(at: url)
            } else {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(cache)
                    try data.write(to: url, options: [.atomic])
                } catch {
                    print("Error clearing playback progress: \(error)")
                }
            }
        }
    }

    static func clearPlaybackProgress(forURL url: URL) {
        state.queue.async {
            var cache = ensurePlaybackProgressCacheLoadedLocked()
            cache = cache.filter { $0.value.audioURL != url.absoluteString }
            state.playbackProgressCache = cache
            let path = fileURL(for: .playbackProgress)
            if cache.isEmpty {
                try? state.fileManager.removeItem(at: path)
            } else {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(cache)
                    try data.write(to: path, options: [.atomic])
                } catch {
                    print("Error clearing playback progress for URL: \(error)")
                }
            }
        }
    }

    static func clearPlaybackProgressCache() {
        state.playbackProgressCache = nil
    }

    /// Waits for pending persistence operations to complete. Used primarily in tests.
    static func waitForPersistenceQueue() {
        state.queue.sync { }
    }
    
    /// Clears the cue cache, forcing a reload from disk on next access
    static func clearCueCache() {
        state.cueCache = nil
    }

    /// Clears the favorites cache, forcing a reload from disk on next access
    static func clearFavoritesCache() {
        state.favoritesCache = nil
    }

    /// Clears the subscriptions cache, forcing a reload from disk on next access
    static func clearSubscriptionsCache() {
        state.subscriptionsCache = nil
    }

    /// Clears the last playback cache, forcing a reload from disk on next access
    static func clearLastPlaybackCache() {
        state.lastPlaybackCache = nil
    }
    
    /// Clears the downloads cache, forcing a reload from disk on next access
    static func clearDownloadsCache() {
        state.downloadsCache = nil
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
        let keys: [PersistenceKeys] = [.favorites, .cue, .lastPlayback, .subscriptions, .downloads, .playbackProgress]
        // Perform removal synchronously to ensure files are deleted before returning
        state.queue.sync {
            for key in keys {
                try? state.fileManager.removeItem(at: fileURL(for: key))
            }
            state.favoritesCache = nil
            state.cueCache = nil
            state.lastPlaybackCache = nil
            state.subscriptionsCache = nil
            state.downloadsCache = nil
            state.playbackProgressCache = nil
        }
    }

    static var hasData: Bool {
        if state.favoritesCache != nil || state.cueCache != nil || state.lastPlaybackCache != nil || state.playbackProgressCache != nil {
            return true
        }
        let keys: [PersistenceKeys] = [.favorites, .cue, .lastPlayback, .playbackProgress]
        return keys.contains { state.fileManager.fileExists(atPath: fileURL(for: $0).path) }
    }
    
    /// Loads a single podcast by feed URL
    /// - Parameter feedUrl: The feed URL of the podcast to load
    /// - Returns: The podcast if found, nil otherwise
    @MainActor
    static func loadPodcast(feedUrl: String?) -> Podcast? {
        guard let feedUrl = feedUrl, !feedUrl.isEmpty else {
            return nil
        }
        
        let podcasts = loadSubscriptionsSync()
        return podcasts.first(where: { $0.feedUrl == feedUrl })
    }
}
