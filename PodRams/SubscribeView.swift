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
    var onPodcastSelect: ((Podcast, Bool) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    @State private var expandedPodcasts: Set<UUID> = []
    @State private var loadingPodcastId: UUID?

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            Text("Subscriptions")
                .font(.title2.weight(.semibold))
                .foregroundColor(primaryText)

            if subscribedPodcasts.isEmpty {
                Text("No subscriptions added.")
                    .foregroundColor(secondaryText)
                    .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(subscribedPodcasts, id: \.id) { podcast in
                            subscriptionDisclosure(for: podcast)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 520)
        .background(AppTheme.color(.background, in: currentMode))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    private func subscriptionDisclosure(for podcast: Podcast) -> some View {
        let isExpanded = Binding(
            get: { expandedPodcasts.contains(podcast.id) },
            set: { expanded in
                if expanded {
                    expandedPodcasts.insert(podcast.id)
                    loadEpisodes(for: podcast)
                } else {
                    expandedPodcasts.remove(podcast.id)
                }
            }
        )

        return DisclosureGroup(isExpanded: isExpanded) {
            episodesStack(for: podcast)
                .padding(.top, 12)
        } label: {
            subscriptionRow(for: podcast)
        }
        .accentColor(primaryText)
        .padding(18)
        .background(rowBackground)
        .overlay(loadingOverlay(for: podcast))
    }

    private func subscriptionRow(for podcast: Podcast) -> some View {
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
                if let feed = podcast.feedUrl {
                    Text(feed)
                        .font(.caption)
                        .foregroundColor(secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                selectPodcast(podcast)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(primaryText)
                    .frame(width: 32, height: 32)
                    .background(controlBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                removeSubscription(podcast)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(removalTint)
                    .frame(width: 32, height: 32)
                    .background(controlBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func episodesStack(for podcast: Podcast) -> some View {
        if podcast.episodes.isEmpty {
            HStack(spacing: 12) {
                LoadingIndicator()
                    .frame(width: 18, height: 18)
                Text("Loading episodes...")
                    .foregroundColor(secondaryText)
            }
            .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
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
                                audioPlayer.playEpisode(episode)
                                PlayedEpisodesManager.shared.markAsPlayed(episode)
                                if let feedUrl = podcast.feedUrl {
                                    PersistenceManager.saveLastPlayback(episode: episode, feedUrl: feedUrl)
                                }
                            }
                        }
                    )
                    .padding(.vertical, 4)
                    .background(AppTheme.color(.surface, in: currentMode).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(AppTheme.color(.surface, in: currentMode))
            .shadow(color: AppTheme.color(.secondaryText, in: currentMode).opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 6, x: 0, y: 4)
    }

    private var controlBackground: Color {
        AppTheme.color(.surface, in: currentMode).opacity(0.9)
    }

    private var removalTint: Color {
        colorScheme == .dark ? Color.red.opacity(0.8) : Color.red.opacity(0.7)
    }

    @ViewBuilder
    private func loadingOverlay(for podcast: Podcast) -> some View {
        if loadingPodcastId == podcast.id {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .overlay(
                    LoadingIndicator()
                        .frame(width: 22, height: 22)
                )
        }
    }

    private func loadEpisodes(for podcast: Podcast) {
        if !podcast.episodes.isEmpty { return }

        loadingPodcastId = podcast.id
        Task {
            let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)

            await MainActor.run {
                if let index = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
                    subscribedPodcasts[index].episodes = episodes
                    if let feedArt = feedArt {
                        subscribedPodcasts[index].feedArtworkURL = feedArt
                    }
                } else {
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
        if let onPodcastSelect {
            onPodcastSelect(podcast, true)
            return
        }

        if podcast.episodes.isEmpty {
            loadingPodcastId = podcast.id
            Task {
                let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                await MainActor.run {
                    if let index = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
                        subscribedPodcasts[index].episodes = episodes
                        if let feedArt = feedArt {
                            subscribedPodcasts[index].feedArtworkURL = feedArt
                        }
                        playAppropriateEpisode(for: subscribedPodcasts[index])
                    } else {
                        podcast.episodes = episodes
                        if let feedArt = feedArt {
                            podcast.feedArtworkURL = feedArt
                        }
                        playAppropriateEpisode(for: podcast)
                    }
                    loadingPodcastId = nil
                }
            }
        } else {
            playAppropriateEpisode(for: podcast)
        }
    }

    private func playAppropriateEpisode(for podcast: Podcast) {
        guard !podcast.episodes.isEmpty else { return }

        selectedPodcast = podcast

        Task {
            if let lastPlayedEpisode = await PersistenceManager.loadLastPlayback(),
               let feedUrl = lastPlayedEpisode.feedUrl,
               feedUrl == podcast.feedUrl,
               let match = podcast.episodes.firstIndex(where: { $0.url == lastPlayedEpisode.url }) {
                await MainActor.run {
                    selectedEpisodeIndex = match
                    audioPlayer.playEpisode(podcast.episodes[match])
                }
            } else {
                await MainActor.run {
                    selectedEpisodeIndex = 0
                    let firstEpisode = podcast.episodes[0]
                    audioPlayer.playEpisode(firstEpisode)
                }
            }
        }
    }
}
