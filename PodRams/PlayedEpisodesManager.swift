import Foundation
import Combine

@MainActor
final class PlayedEpisodesManager: ObservableObject {
    static let shared = PlayedEpisodesManager()
    
    private let playedEpisodesKey = "playedEpisodes"
    
    @Published var playedEpisodes: Set<String> = []
    
    private init() {
        loadPlayedEpisodes()
    }
    
    func markAsPlayed(_ episode: PodcastEpisode) {
        playedEpisodes.insert(episode.id)
        savePlayedEpisodes()
        objectWillChange.send()
    }
    
    func hasBeenPlayed(_ episode: PodcastEpisode) -> Bool {
        playedEpisodes.contains(episode.id)
    }
    
    func loadPlayedEpisodes() {
        if let data = UserDefaults.standard.data(forKey: playedEpisodesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            playedEpisodes = decoded
            objectWillChange.send()
        }
    }
    
    private func savePlayedEpisodes() {
        if let encoded = try? JSONEncoder().encode(playedEpisodes) {
            UserDefaults.standard.set(encoded, forKey: playedEpisodesKey)
        }
    }
} 
