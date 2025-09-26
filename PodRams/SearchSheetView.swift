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

    // Add a closure to handle podcast selection using ContentView's method
    var onPodcastSelect: ((Podcast, Bool) -> Void)?

    var dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            Text("Search Podcasts")
                .font(.headline)
                .foregroundColor(primaryText)

            searchField

            if podcastFetcher.podcasts.isEmpty {
                Text("No results yet.")
                    .foregroundColor(secondaryText)
                    .padding(.top, 32)
            } else {
                resultsList
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(AppTheme.color(.background, in: currentMode))
        .frame(minWidth: 420, minHeight: 520)
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

    private var searchField: some View {
        TextField("Search Podcasts", text: $podcastFetcher.searchQuery)
            .textFieldStyle(.plain)
            .textCase(nil)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.color(.surface, in: currentMode))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.color(.secondaryText, in: currentMode).opacity(0.12))
                    )
            )
            .foregroundColor(primaryText)
            .font(.body)
            .onSubmit { Task { await podcastFetcher.searchPodcasts() } }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(podcastFetcher.podcasts) { podcast in
                    HStack(spacing: 12) {
                        CachedAsyncImage(
                            url: podcast.feedArtworkURL,
                            width: 44,
                            height: 44
                        )
                        .cornerRadius(8)

                        Text(podcast.title)
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        favoriteIcon(for: podcast)

                        subscriptionIcon(for: podcast)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .onTapGesture { selectPodcast(podcast) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.color(.surface, in: currentMode))
            .shadow(color: AppTheme.color(.secondaryText, in: currentMode).opacity(0.08), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func favoriteIcon(for podcast: Podcast) -> some View {
        let enabled = isFavorite(podcast)
        let symbol = enabled ? "star.fill" : "star"
        Image(systemName: symbol)
            .foregroundColor(enabled ? AppTheme.accent : secondaryText)
            .onTapGesture { toggleFavorite(podcast) }
    }

    @ViewBuilder
    private func subscriptionIcon(for podcast: Podcast) -> some View {
        if isSubscribed(podcast) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.accent)
        } else {
            Image(systemName: "rectangle.and.paperclip")
                .foregroundColor(primaryText)
                .onTapGesture { toggleSubscription(podcast) }
        }
    }

    private func selectPodcast(_ podcast: Podcast) {
        // If we have an external handler, use it
        if let onPodcastSelect = onPodcastSelect {
            onPodcastSelect(podcast, true) // true for autoPlay
            dismiss()
            return
        }
        
        // Otherwise, use the original implementation
        Task {
            selectedPodcast = podcast
            isCuePlaying = false
            podcastFetcher.searchQuery = ""

            await podcastFetcher.fetchEpisodes(for: podcast)

            if let firstEpisode = podcast.episodes.first {
                DispatchQueue.main.async {
                    selectedEpisodeIndex = 0
                    audioPlayer.playEpisode(firstEpisode)
                }
            }
            dismiss()
        }
    }

    private func isFavorite(_ podcast: Podcast) -> Bool {
        // Use feedUrl for comparison instead of id
        guard let feedUrl = podcast.feedUrl else { return false }
        return favoritePodcasts.contains { $0.feedUrl == feedUrl }
    }
    
    private func toggleFavorite(_ podcast: Podcast) {
        guard let feedUrl = podcast.feedUrl else { return }
        
        if let idx = favoritePodcasts.firstIndex(where: { $0.feedUrl == feedUrl }) {
            // Create a new array to avoid direct binding modification
            var updatedFavorites = favoritePodcasts
            updatedFavorites.remove(at: idx)
            favoritePodcasts = updatedFavorites
        } else {
            // Create a new array to avoid direct binding modification
            var updatedFavorites = favoritePodcasts
            updatedFavorites.append(podcast)
            favoritePodcasts = updatedFavorites
        }
        PersistenceManager.saveFavorites(favoritePodcasts)
    }
    
    private func isSubscribed(_ podcast: Podcast) -> Bool {
        // Use feedUrl for comparison instead of id
        guard let feedUrl = podcast.feedUrl else { return false }
        return subscribedPodcasts.contains { $0.feedUrl == feedUrl }
    }
    
    private func toggleSubscription(_ podcast: Podcast) {
        guard let feedUrl = podcast.feedUrl else { 
            print("Warning: Cannot subscribe to podcast without feed URL")
            return 
        }
        
        if let idx = subscribedPodcasts.firstIndex(where: { $0.feedUrl == feedUrl }) {
            // Remove from subscriptions
            var updatedSubscriptions = subscribedPodcasts
            updatedSubscriptions.remove(at: idx)
            subscribedPodcasts = updatedSubscriptions
            print("Removed subscription for: \(podcast.title)")
        } else {
            // Add to subscriptions
            var updatedSubscriptions = subscribedPodcasts
            updatedSubscriptions.append(podcast)
            subscribedPodcasts = updatedSubscriptions
            print("Added subscription for: \(podcast.title)")
        }
        
        // Save updated subscriptions
        PersistenceManager.saveSubscriptions(subscribedPodcasts)
        print("Subscriptions saved. Total: \(subscribedPodcasts.count)")
    }
}
