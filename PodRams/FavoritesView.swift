//
//  FavoritesView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// FavoritesView.swift

import SwiftUI
import Combine
import AppKit

struct FavoritesView: View {
    @Binding var favoritePodcasts: [Podcast]
    @Binding var selectedPodcast: Podcast?
    @Binding var selectedEpisodeIndex: Int?
    @ObservedObject var audioPlayer: AudioPlayer
    @ObservedObject var podcastFetcher: PodcastFetcher
    @Environment(\.dismiss) var dismiss
    
    @State private var loadingPodcastId: UUID?

    var body: some View {
        VStack {
            Text("Favorites")
                .font(.title)
                .bold()
                .padding()

            if favoritePodcasts.isEmpty {
                Text("No favorite podcasts added.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List {
                    ForEach(favoritePodcasts, id: \.id) { podcast in
                        HStack(spacing: 8) {
                            Button {
                                loadPodcast(podcast)
                            } label: {
                                HStack(spacing: 8) {
                                    CachedAsyncImage(
                                        url: podcast.feedArtworkURL,
                                        width: 40,
                                        height: 40
                                    )
                                    .cornerRadius(4)

                                    Text(podcast.title)
                                        .padding(.vertical, 8)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(loadingPodcastId == podcast.id)
                            .overlay(
                                loadingPodcastId == podcast.id ?
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.5)
                                    : nil
                            )

                            Button {
                                removeFromFavorites(podcast)
                            } label: {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
                .frame(minHeight: 200)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 10)
        .onAppear {
            preloadFavorites()
        }
    }

    private func loadPodcast(_ podcast: Podcast) {
        loadingPodcastId = podcast.id
        
        if let firstCachedEpisode = podcast.episodes.first {
            audioPlayer.playAudio(url: firstCachedEpisode.url)
            selectedPodcast = podcast
            selectedEpisodeIndex = 0
            loadingPodcastId = nil
            dismiss()
            return
        }
        
        Task(priority: .userInitiated) {
            let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
            
            await MainActor.run {
                podcast.episodes = episodes
                if let fa = feedArt { podcast.feedArtworkURL = fa }
                selectedPodcast = podcast
                
                if let first = episodes.first {
                    selectedEpisodeIndex = 0
                    audioPlayer.playAudio(url: first.url)
                }
                
                loadingPodcastId = nil
                dismiss()
            }
        }
    }
    
    private func preloadFavorites() {
        Task {
            for podcast in favoritePodcasts where podcast.episodes.isEmpty {
                let _ = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                if let firstEpisode = podcast.episodes.first {
                    audioPlayer.preloadAudio(url: firstEpisode.url)
                }
            }
        }
    }

    private func removeFromFavorites(_ podcast: Podcast) {
        if let idx = favoritePodcasts.firstIndex(where: { $0.id == podcast.id }) {
            favoritePodcasts.remove(at: idx)
            PersistenceManager.saveFavorites(favoritePodcasts)
        }
    }
}
