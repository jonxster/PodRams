//
//  SubscribeView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//
import SwiftUI

struct SubscribeView: View {
    @Binding var subscribedPodcasts: [Podcast]
    @Binding var selectedPodcast: Podcast?
    @Binding var selectedEpisodeIndex: Int?
    @ObservedObject var podcastFetcher: PodcastFetcher
    @ObservedObject var audioPlayer: AudioPlayer
    
    // Add a closure to handle podcast selection using ContentView's method
    var onPodcastSelect: ((Podcast, Bool) -> Void)?
    
    @State private var expandedPodcasts: Set<UUID> = []
    @State private var loadingPodcastId: UUID?
    @State private var cue: [PodcastEpisode] = []
    
    var body: some View {
        VStack {
            Text("Subscriptions")
                .font(.title)
                .padding()
            if subscribedPodcasts.isEmpty {
                Text("No subscriptions added.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List {
                    ForEach(subscribedPodcasts, id: \.id) { podcast in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedPodcasts.contains(podcast.id) },
                            set: { expanded in
                                if expanded {
                                    expandedPodcasts.insert(podcast.id)
                                    loadEpisodes(for: podcast)
                                } else {
                                    expandedPodcasts.remove(podcast.id)
                                }
                            }
                        )) {
                            if podcast.episodes.isEmpty {
                                HStack {
                                    Text("Loading episodes...")
                                        .foregroundColor(.gray)
                                    LoadingIndicator()
                                        .frame(width: 16, height: 16)
                                }
                            } else {
                                ForEach(podcast.episodes, id: \.id) { episode in
                                    let isPlaying = selectedPodcast == podcast && 
                                                   selectedEpisodeIndex == podcast.episodes.firstIndex(where: { $0.id == episode.id })
                                    
                                    let config = EpisodeRowConfiguration(
                                        episode: episode,
                                        index: podcast.episodes.firstIndex(where: { $0.id == episode.id }) ?? 0,
                                        isPlaying: isPlaying,
                                        isInCue: cue.contains { $0.url.absoluteString == episode.url.absoluteString },
                                        currentTime: isPlaying ? audioPlayer.currentTime : 0,
                                        duration: isPlaying ? audioPlayer.duration : (episode.duration ?? 0),
                                        audioPlayer: audioPlayer,
                                        selectedPodcast: podcast,
                                        onSelect: { idx in
                                            selectedPodcast = podcast
                                            if let index = podcast.episodes.firstIndex(where: { $0.id == episode.id }) {
                                                selectedEpisodeIndex = index
                                                
                                                // Use local URL if downloaded, otherwise use the remote URL
                                                let playURL = DownloadManager.shared.localURL(for: episode) ?? episode.url
                                                audioPlayer.playAudio(url: playURL)
                                                
                                                // Mark as played and save last playback
                                                PlayedEpisodesManager.shared.markAsPlayed(episode)
                                                if let feedUrl = podcast.feedUrl {
                                                    PersistenceManager.saveLastPlayback(episode: episode, feedUrl: feedUrl)
                                                }
                                            }
                                        },
                                        onToggleCue: { episode in
                                            // Add or remove from cue
                                            if let idx = cue.firstIndex(where: { $0.url.absoluteString == episode.url.absoluteString }) {
                                                var updatedCue = cue
                                                updatedCue.remove(at: idx)
                                                cue = updatedCue
                                                PersistenceManager.saveCue(cue, feedUrl: episode.feedUrl)
                                                NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                                            } else {
                                                var newEpisode = episode
                                                newEpisode.podcastName = podcast.title
                                                
                                                // Generate a unique ID for the cue version of the episode
                                                let cueId = "cue_\(UUID().uuidString)_\(episode.url.absoluteString)"
                                                newEpisode = PodcastEpisode(
                                                    id: cueId,
                                                    title: newEpisode.title,
                                                    url: newEpisode.url,
                                                    artworkURL: newEpisode.artworkURL,
                                                    duration: newEpisode.duration,
                                                    showNotes: newEpisode.showNotes,
                                                    feedUrl: newEpisode.feedUrl,
                                                    podcastName: newEpisode.podcastName
                                                )
                                                var updatedCue = cue
                                                updatedCue.append(newEpisode)
                                                cue = updatedCue
                                                PersistenceManager.saveCue(cue, feedUrl: episode.feedUrl)
                                                NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                                            }
                                        },
                                        onDownload: { episode in
                                            DownloadManager.shared.downloadEpisode(episode)
                                        }
                                    )
                                    
                                    // Render the episode row using the configured settings
                                    ConfiguredEpisodeRow(config: config)
                                        .padding(.vertical, 4)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                CachedAsyncImage(
                                    url: podcast.feedArtworkURL,
                                    width: 40,
                                    height: 40
                                )
                                .cornerRadius(4)
                                
                                Text(podcast.title)
                                    .onTapGesture {
                                        selectPodcast(podcast)
                                    }
                                
                                Spacer()
                                
                                Button(action: {
                                    removeSubscription(podcast)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            Task {
                cue = await PersistenceManager.loadCue()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CueUpdated"))) { _ in
            Task {
                cue = await PersistenceManager.loadCue()
            }
        }
    }
    
    private func loadEpisodes(for podcast: Podcast) {
        if podcast.episodes.isEmpty {
            loadingPodcastId = podcast.id
            Task {
                let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                await MainActor.run {
                    podcast.episodes = episodes
                    if let feedArt = feedArt {
                        podcast.feedArtworkURL = feedArt
                    }
                    loadingPodcastId = nil
                }
            }
        }
    }
    
    private func removeSubscription(_ podcast: Podcast) {
        if let idx = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
            subscribedPodcasts.remove(at: idx)
            PersistenceManager.saveSubscriptions(subscribedPodcasts)
        }
    }
    
    private func selectPodcast(_ podcast: Podcast) {
        // If we have an external handler, use it
        if let onPodcastSelect = onPodcastSelect {
            onPodcastSelect(podcast, true) // true for autoPlay
            return
        }
        
        // Otherwise, use the original implementation
        // First, load episodes if they're not already loaded
        if podcast.episodes.isEmpty {
            loadEpisodes(for: podcast)
            // Set a loading indicator
            loadingPodcastId = podcast.id
            
            // Fetch episodes and then determine which one to play
            Task {
                let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                
                await MainActor.run {
                    podcast.episodes = episodes
                    if let feedArt = feedArt {
                        podcast.feedArtworkURL = feedArt
                    }
                    
                    // Now that episodes are loaded, determine which one to play
                    playAppropriateEpisode(for: podcast)
                    
                    loadingPodcastId = nil
                }
            }
        } else {
            // Episodes already loaded, determine which one to play
            playAppropriateEpisode(for: podcast)
        }
    }
    
    private func playAppropriateEpisode(for podcast: Podcast) {
        guard !podcast.episodes.isEmpty else { return }
        
        // Set the selected podcast
        selectedPodcast = podcast
        
        // Try to find the last played episode for this podcast
        Task {
            if let lastPlayedEpisode = await PersistenceManager.loadLastPlayback(),
               let feedUrl = lastPlayedEpisode.feedUrl,
               feedUrl == podcast.feedUrl {
                
                // Find the matching episode in the current podcast
                if let index = podcast.episodes.firstIndex(where: { $0.url.absoluteString == lastPlayedEpisode.url.absoluteString }) {
                    selectedEpisodeIndex = index
                    audioPlayer.playAudio(url: podcast.episodes[index].url)
                    
                    // Mark as played
                    PlayedEpisodesManager.shared.markAsPlayed(podcast.episodes[index])
                    return
                }
            }
            
            // If no last played episode found or it doesn't match, play the first (latest) episode
            selectedEpisodeIndex = 0
            audioPlayer.playAudio(url: podcast.episodes[0].url)
            
            // Mark as played and save this as the last played episode
            PlayedEpisodesManager.shared.markAsPlayed(podcast.episodes[0])
            if let feedUrl = podcast.feedUrl {
                PersistenceManager.saveLastPlayback(episode: podcast.episodes[0], feedUrl: feedUrl)
            }
        }
    }
}
