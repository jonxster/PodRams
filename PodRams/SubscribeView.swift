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
                            // Wrap episode content in a container with minimum width constraints
                            VStack(spacing: 0) {
                                if podcast.episodes.isEmpty {
                                    HStack {
                                        Text("Loading episodes...")
                                            .foregroundColor(.gray)
                                        LoadingIndicator()
                                            .frame(width: 16, height: 16)
                                    }
                                    .frame(minWidth: 200)
                                    .padding(.vertical, 8)
                                } else {
                                    ForEach(podcast.episodes, id: \.id) { episode in
                                        let isPlaying = selectedPodcast == podcast && 
                                                       selectedEpisodeIndex == podcast.episodes.firstIndex(where: { $0.id == episode.id })
                                        
                                        SimpleEpisodeRow(
                                            episode: episode,
                                            isPlaying: isPlaying,
                                            onSelect: {
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
                                            }
                                        )
                                        .frame(minWidth: 200) // Ensure minimum width for episode rows
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading) // Ensure proper width distribution
                        } label: {
                            HStack(spacing: 8) {
                                CachedAsyncImage(
                                    url: podcast.feedArtworkURL,
                                    width: 40,
                                    height: 40
                                )
                                .cornerRadius(4)
                                .frame(width: 40, height: 40) // Explicit frame to prevent negative width calculations
                                .onAppear {
                                    print("🖼️ Artwork for \(podcast.title): \(podcast.feedArtworkURL?.absoluteString ?? "nil")")
                                }
                                
                                Button(action: {
                                    selectPodcast(podcast)
                                }) {
                                    HStack(spacing: 4) {
                                        Text(podcast.title)
                                            .foregroundColor(.primary)
                                            .font(.headline)
                                            .lineLimit(2) // Prevent text from causing layout issues
                                        
                                        // Show loading indicator when this podcast is being loaded
                                        if loadingPodcastId == podcast.id {
                                            LoadingIndicator()
                                                .frame(width: 12, height: 12)
                                        }
                                    }
                                    .frame(minWidth: 100) // Ensure minimum width for text content
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(loadingPodcastId == podcast.id)
                                
                                Spacer(minLength: 8) // Add minimum spacing
                                
                                Button(action: {
                                    removeSubscription(podcast)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .frame(width: 24, height: 24) // Fixed size for trash button
                            }
                            .frame(minWidth: 200) // Ensure minimum width for the entire label
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .frame(minWidth: 350) // Ensure the list itself has sufficient width
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
    
    private func loadEpisodes(for podcast: Podcast) {
        // Skip loading if episodes are already loaded
        if !podcast.episodes.isEmpty {
            return
        }
        
        loadingPodcastId = podcast.id
        Task {
            print("🔄 Loading episodes for podcast: \(podcast.title)")
            let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
            
            await MainActor.run {
                // Find the podcast in the subscribed podcasts array and update it
                if let index = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
                    subscribedPodcasts[index].episodes = episodes
                    if let feedArt = feedArt {
                        subscribedPodcasts[index].feedArtworkURL = feedArt
                    }
                    print("✅ Loaded \(episodes.count) episodes for \(podcast.title)")
                } else {
                    // Fallback - update the passed podcast object
                    podcast.episodes = episodes
                    if let feedArt = feedArt {
                        podcast.feedArtworkURL = feedArt
                    }
                }
                loadingPodcastId = nil
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
            loadingPodcastId = podcast.id
            
            // Fetch episodes and then determine which one to play
            Task {
                print("🔄 Loading episodes for selected podcast: \(podcast.title)")
                let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                
                await MainActor.run {
                    // Find the podcast in the subscribed podcasts array and update it
                    if let index = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
                        subscribedPodcasts[index].episodes = episodes
                        if let feedArt = feedArt {
                            subscribedPodcasts[index].feedArtworkURL = feedArt
                        }
                        print("✅ Loaded \(episodes.count) episodes for selected podcast: \(podcast.title)")
                        
                        // Now that episodes are loaded, determine which one to play using the updated podcast
                        playAppropriateEpisode(for: subscribedPodcasts[index])
                    } else {
                        // Fallback - update the passed podcast object
                        podcast.episodes = episodes
                        if let feedArt = feedArt {
                            podcast.feedArtworkURL = feedArt
                        }
                        
                        // Now that episodes are loaded, determine which one to play
                        playAppropriateEpisode(for: podcast)
                    }
                    
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
