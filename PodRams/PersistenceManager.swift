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
        queue.async {
            do {
                let encoded = try encoder.encode(data)
                try encoded.write(to: fileURL(for: key), options: [.atomic])
            } catch {
                print("Error saving \(key.rawValue): \(error)")
            }
        }
    }
    
    private static func loadData<T: Decodable>(from key: PersistenceKeys) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async {
                let url = fileURL(for: key)
                guard fileManager.fileExists(atPath: url.path) else {
                    DispatchQueue.main.async {
                        continuation.resume(returning: nil)
                    }
                    return
                }
                do {
                    let data = try Data(contentsOf: url)
                    let result = try decoder.decode(T.self, from: data)
                    DispatchQueue.main.async {
                        continuation.resume(returning: result)
                    }
                } catch {
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
        guard let feedUrl = feedUrl, !feedUrl.isEmpty else {
            queue.async { try? fileManager.removeItem(at: fileURL(for: .cue)) }
            cueCache = nil
            return
        }
        
        let persistedEpisodes = episodes.compactMap { episode -> PersistedEpisode? in
            let urlString = episode.url.absoluteString
            guard !urlString.isEmpty else {
                print("Warning: Skipping episode with invalid URL: \(episode.title)")
                return nil
            }
            return PersistedEpisode(
                feedUrl: feedUrl,
                title: episode.title,
                audioURL: urlString,
                duration: episode.duration
            )
        }
        cueCache = episodes
        saveData(persistedEpisodes, to: .cue)
    }
    
    static func loadCue() async -> [PodcastEpisode] {
        if let cached = cueCache { return cached }
        let persisted: [PersistedEpisode]? = await loadData(from: .cue)
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
                feedUrl: pe.feedUrl
            )
        } ?? []
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
            duration: episode.duration
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
                feedUrl: pe.feedUrl
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
    
    static func clearAll() {
        let keys: [PersistenceKeys] = [.favorites, .cue, .lastPlayback, .subscriptions, .downloads]
        queue.async {
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
}
