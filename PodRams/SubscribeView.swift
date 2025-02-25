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
    @ObservedObject var podcastFetcher: PodcastFetcher
    @ObservedObject var audioPlayer: AudioPlayer
    
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
                            if podcast.episodes.isEmpty {
                                HStack {
                                    Text("Loading episodes...")
                                        .foregroundColor(.gray)
                                    LoadingIndicator()
                                        .frame(width: 16, height: 16)
                                }
                            } else {
                                ForEach(podcast.episodes, id: \.id) { episode in
                                    HStack {
                                        Text(episode.title)
                                            .lineLimit(1)
                                        Spacer()
                                        DownloadButton(episode: episode)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPodcast = podcast
                                        if podcast.episodes.firstIndex(where: { $0.id == episode.id }) != nil {
                                            if let localURL = DownloadManager.shared.localURL(for: episode) {
                                                audioPlayer.playAudio(url: localURL)
                                            } else {
                                                audioPlayer.playAudio(url: episode.url)
                                            }
                                        }
                                    }
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
}
