//
//  SearchSheetView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI
import Combine
import AppKit

struct SearchSheetView: View {
    @ObservedObject var podcastFetcher: PodcastFetcher
    @Binding var selectedPodcast: Podcast?
    @Binding var selectedEpisodeIndex: Int?
    @ObservedObject var audioPlayer: AudioPlayer
    @Binding var isCuePlaying: Bool
    @Binding var favoritePodcasts: [Podcast]
    @Binding var subscribedPodcasts: [Podcast] // New: subscription binding

    var dismiss: () -> Void

    var body: some View {
        VStack {
            Text("Search Podcasts")
                .font(.headline)
                .padding()

            TextField("Search Podcasts", text: $podcastFetcher.searchQuery)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding([.horizontal, .bottom])
                .onSubmit {
                    Task {
                        await podcastFetcher.searchPodcasts()
                    }
                }

            if podcastFetcher.podcasts.isEmpty {
                Text("No results yet.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List(podcastFetcher.podcasts) { podcast in
                    HStack(spacing: 8) {
                        CachedAsyncImage(
                            url: podcast.feedArtworkURL,
                            width: 40,
                            height: 40
                        )
                        .cornerRadius(4)

                        Text(podcast.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Image(systemName: isFavorite(podcast) ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .onTapGesture {
                                toggleFavorite(podcast)
                            }
                        
                        // Only show subscription button if not already subscribed
                        if !isSubscribed(podcast) {
                            Image(systemName: "rectangle.and.paperclip")
                                .foregroundColor(.blue)
                                .onTapGesture {
                                    toggleSubscription(podcast)
                                }
                        } else {
                            // Show a checkmark or other indicator that it's already subscribed
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectPodcast(podcast)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(PlainListStyle())
            }

            Spacer()
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private func selectPodcast(_ podcast: Podcast) {
        Task {
            selectedPodcast = podcast
            isCuePlaying = false
            podcastFetcher.searchQuery = ""

            await podcastFetcher.fetchEpisodes(for: podcast)

            if let firstEpisode = podcast.episodes.first {
                DispatchQueue.main.async {
                    selectedEpisodeIndex = 0
                    audioPlayer.playAudio(url: firstEpisode.url)
                }
            }
            dismiss()
        }
    }

    private func isFavorite(_ podcast: Podcast) -> Bool {
        favoritePodcasts.contains { $0.id == podcast.id }
    }
    
    private func toggleFavorite(_ podcast: Podcast) {
        if let idx = favoritePodcasts.firstIndex(where: { $0.id == podcast.id }) {
            favoritePodcasts.remove(at: idx)
        } else {
            favoritePodcasts.append(podcast)
        }
        PersistenceManager.saveFavorites(favoritePodcasts)
    }
    
    private func isSubscribed(_ podcast: Podcast) -> Bool {
        subscribedPodcasts.contains { $0.id == podcast.id }
    }
    
    private func toggleSubscription(_ podcast: Podcast) {
        if let idx = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
            subscribedPodcasts.remove(at: idx)
        } else {
            // Check if a podcast with the same feed URL already exists
            if let feedUrl = podcast.feedUrl, 
               !subscribedPodcasts.contains(where: { $0.feedUrl == feedUrl }) {
                subscribedPodcasts.append(podcast)
            }
        }
        PersistenceManager.saveSubscriptions(subscribedPodcasts)
    }
}
