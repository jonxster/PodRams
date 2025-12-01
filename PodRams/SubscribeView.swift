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
    var onDismiss: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    @State private var expandedPodcasts: Set<UUID> = []
    @State private var loadingPodcastId: UUID?
    @State private var prefetchTask: Task<Void, Never>?

    var body: some View {
        GlassEffectContainer(spacing: 20) {
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
        .compatGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            if prefetchTask == nil {
                prefetchTask = Task(name: "subscribe-prefetch-missing") { await prefetchMissingEpisodes() }
            }
        }
        .onDisappear {
            prefetchTask?.cancel()
            prefetchTask = nil
        }
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
        .applyFocusEffectDisabled()
    }

    private func subscriptionRow(for podcast: Podcast) -> some View {
        HStack(spacing: 10) {
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
            .help(LocalizedStringKey("Play"))
            .applyFocusEffectDisabled()
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
            .help(LocalizedStringKey("Unsubscribe"))
            .applyFocusEffectDisabled()
            .buttonStyle(.plain)
        }
    }
    
    /// Prefetch episodes for subscriptions that have not been loaded yet to keep expansion instant.
    private func prefetchMissingEpisodes() async {
        let targets = await MainActor.run { subscribedPodcasts.filter { $0.episodes.isEmpty } }
        guard !targets.isEmpty else { return }
        
        await withTaskGroup(of: Void.self) { group in
            for podcast in targets.prefix(4) { // limit upfront work to keep UI snappy
                group.addTask(name: "prefetch-missing-\(podcast.id.uuidString.prefix(8))") {
                    let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                    await MainActor.run {
                        guard let idx = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) else { return }
                        subscribedPodcasts[idx].episodes = episodes
                        if let feedArt {
                            subscribedPodcasts[idx].feedArtworkURL = feedArt
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func episodesStack(for podcast: Podcast) -> some View {
        if podcast.episodes.isEmpty {
            HStack(spacing: 12) {
                LoadingIndicator()
                    .frame(width: 20, height: 20)
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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppTheme.color(.surface, in: currentMode))

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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .overlay(
                    LoadingIndicator()
                        .frame(width: 20, height: 20)
                )
        }
    }

    private func loadEpisodes(for podcast: Podcast) {
        if !podcast.episodes.isEmpty { return }

        loadingPodcastId = podcast.id
        Task(name: "load-episodes-\(podcast.id.uuidString.prefix(8))") {
            let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)

            await MainActor.run {
                if let index = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
                    subscribedPodcasts[index].episodes = episodes
                    if let feedArt = feedArt {
                        subscribedPodcasts[index].feedArtworkURL = feedArt
                    }
                    persistSubscriptionSnapshot()
                } else {
                    podcast.episodes = episodes
                    if let feedArt = feedArt {
                        podcast.feedArtworkURL = feedArt
                    }
                    persistSubscriptionSnapshot()
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
            onDismiss?()
            return
        }

        if podcast.episodes.isEmpty {
            loadingPodcastId = podcast.id
            Task(name: "select-play-\(podcast.id.uuidString.prefix(8))") {
                let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                await MainActor.run {
                    if let index = subscribedPodcasts.firstIndex(where: { $0.id == podcast.id }) {
                        subscribedPodcasts[index].episodes = episodes
                        if let feedArt = feedArt {
                            subscribedPodcasts[index].feedArtworkURL = feedArt
                        }
                        persistSubscriptionSnapshot()
                        playFirstEpisode(for: subscribedPodcasts[index])
                    } else {
                        podcast.episodes = episodes
                        if let feedArt = feedArt {
                            podcast.feedArtworkURL = feedArt
                        }
                        persistSubscriptionSnapshot()
                        playFirstEpisode(for: podcast)
                    }
                    loadingPodcastId = nil
                }
            }
        } else {
            playFirstEpisode(for: podcast)
        }
    }

    private func playFirstEpisode(for podcast: Podcast) {
        guard !podcast.episodes.isEmpty else { return }

        let firstEpisode = podcast.episodes[0]

        Task(name: "play-first-\(podcast.id.uuidString.prefix(8))") {
            await MainActor.run {
                selectedPodcast = podcast
                selectedEpisodeIndex = 0

                audioPlayer.playEpisode(firstEpisode)

                onDismiss?()
            }
        }
    }

    private func persistSubscriptionSnapshot() {
        let maxEpisodes = MemoryOptimizationManager.shared.maxEpisodesPerPodcast
        let snapshot = subscribedPodcasts.reduce(into: [String: [PodcastEpisode]]()) { acc, podcast in
            if let feed = podcast.feedUrl, !feed.isEmpty, !podcast.episodes.isEmpty {
                acc[feed] = Array(podcast.episodes.prefix(maxEpisodes))
            }
        }
        PersistenceManager.saveSubscriptionEpisodesSnapshot(snapshot)
    }
}

private extension View {
    @ViewBuilder
    func applyFocusEffectDisabled() -> some View {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
        #else
        self
        #endif
    }
}
