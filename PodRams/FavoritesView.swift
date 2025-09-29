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
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var loadingPodcastId: UUID?
    @Namespace private var badgeNamespace

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            Text("Favorites")
                .font(.title2.weight(.semibold))
                .foregroundColor(primaryText)

            if favoritePodcasts.isEmpty {
                Text("No favorite podcasts added.")
                    .foregroundColor(secondaryText)
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(favoritePodcasts, id: \.id) { podcast in
                            favoriteRow(for: podcast)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 340)
        .background(AppTheme.color(.background, in: currentMode))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { preloadFavorites() }
    }

    private var currentMode: AppTheme.Mode {
        colorScheme == .dark ? .dark : .light
    }

    private var primaryText: Color {
        AppTheme.color(.primaryText, in: currentMode)
    }

    private var secondaryText: Color {
        AppTheme.color(.secondaryText, in: currentMode)
    }

    private func favoriteRow(for podcast: Podcast) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                CachedAsyncImage(
                    url: podcast.feedArtworkURL,
                    width: 48,
                    height: 48
                )
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.title)
                        .font(.headline)
                        .foregroundColor(primaryText)

                    if let feedUrl = podcast.feedUrl {
                        Text(feedUrl)
                            .font(.caption)
                            .foregroundColor(secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    loadPodcast(podcast)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(primaryText)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(loadingPodcastId == podcast.id)

                Button {
                    removeFromFavorites(podcast)
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(favoriteTint)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            GlassBadgeView(
                symbolName: "waveform.circle",
                title: "Episodes \(podcast.episodes.count)",
                subtitle: podcast.feedArtworkURL == nil ? "Artwork pending" : "Artwork cached",
                tint: favoriteTint,
                namespace: badgeNamespace,
                glassID: podcast.id.uuidString
            )
        }
        .padding(16)
        .background(rowBackground)
        .overlay(loadingOverlay(for: podcast))
    }

    private var controlBackground: Color {
        AppTheme.color(.surface, in: currentMode).opacity(0.85)
    }

    private var favoriteTint: Color {
        colorScheme == .dark ? AppTheme.accent : Color(hex: 0xFFAA33)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.color(.surface, in: currentMode))
            .shadow(color: AppTheme.color(.secondaryText, in: currentMode).opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 6, x: 0, y: 4)
    }

    @ViewBuilder
    private func loadingOverlay(for podcast: Podcast) -> some View {
        if loadingPodcastId == podcast.id {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.1))
                .overlay(
                    LoadingIndicator()
                        .frame(width: 22, height: 22)
                )
        } else {
            EmptyView()
        }
    }

    private func loadPodcast(_ podcast: Podcast) {
        loadingPodcastId = podcast.id
        
        if let firstCachedEpisode = podcast.episodes.first {
            audioPlayer.playEpisode(firstCachedEpisode)
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
                    audioPlayer.playEpisode(first)
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
            var updatedFavorites = favoritePodcasts
            updatedFavorites.remove(at: idx)
            favoritePodcasts = updatedFavorites
            
            PersistenceManager.saveFavorites(favoritePodcasts)
        }
    }
}
