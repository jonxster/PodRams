//
// EpisodeListView.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI

/// Configuration model for an individual episode row.
/// This structure bundles all required data and callback closures for rendering an episode row.
struct EpisodeRowConfiguration {
    let episode: PodcastEpisode       // The episode to display.
    let index: Int                    // The episode's position in the list.
    let isPlaying: Bool               // Whether this episode is currently playing.
    let isInCue: Bool                 // Whether this episode is in the play queue.
    let currentTime: Double           // Current playback time (if playing).
    let duration: Double              // Total duration of the episode.
    let audioPlayer: AudioPlayer      // Reference to the shared audio player.
    let selectedPodcast: Podcast?     // The currently selected podcast.
    let onSelect: (Int) -> Void       // Callback when the episode is selected.
    let onToggleCue: (PodcastEpisode) -> Void  // Callback to add/remove episode from cue.
    let onDownload: (PodcastEpisode) -> Void   // Callback to initiate downloading of the episode.
}

/// A view that wraps an EpisodeRow using a pre-configured EpisodeRowConfiguration.
/// This view sets up the callbacks and content shape for interaction.
struct ConfiguredEpisodeRow: View {
    let config: EpisodeRowConfiguration

    var body: some View {
        EpisodeRow(
            episode: config.episode,
            isPlaying: config.isPlaying,
            isInCue: config.isInCue,
            currentTime: config.currentTime,
            duration: config.duration,
            audioPlayer: config.audioPlayer,
            onSeek: { newTime in
                // Seek to the specified time using the shared audio player.
                config.audioPlayer.seek(to: newTime)
            },
            onSelect: {
                // Invoke the selection callback with the episode index.
                config.onSelect(config.index)
            },
            onToggleCue: {
                // Toggle the cue state for this episode.
                config.onToggleCue(config.episode)
            },
            onDownload: {
                // Start the download process for this episode.
                config.onDownload(config.episode)
            }
        )
        .contentShape(Rectangle()) // Makes the entire row tappable.
    }
}

/// A view displaying a list of podcast episodes.
/// It supports selecting an episode, toggling its inclusion in the cue, and downloading episodes.
struct EpisodeListView: View {
    let episodes: [PodcastEpisode]      // Array of episodes to display.
    let selectedEpisodeIndex: Int?      // Index of the currently playing/selected episode.
    let cue: [PodcastEpisode]           // Current list of episodes in the play queue.
    let audioPlayer: AudioPlayer        // Reference to the audio player for playback control.
    let selectedPodcast: Podcast?       // The podcast whose episodes are being displayed.
    @Binding var selectedIndex: Int?    // Binding to the selected episode index for external control.
    @Binding var cueList: [PodcastEpisode]  // Binding to the play queue, enabling real-time updates.
    @Binding var isCuePlaying: Bool
    
    // Add a timer to force UI updates - increase frequency for smooth countdown
    @State private var refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    @State private var lastRefreshTime: Date = Date()
    @State private var sortedEpisodesCache: [PodcastEpisode] = []
    @State private var cachedEpisodeIDs: [String] = []
    @State private var episodeIndexMap: [String: Int] = [:]
    
    /// Handles selection of an episode.
    /// Stops current playback, sets the new episode index, and starts playback with a slight delay.
    private func handleEpisodeSelect(_ index: Int, episode: PodcastEpisode) {
        // Optimize by finding index more efficiently
        if let actualIndex = episodes.firstIndex(where: { $0.id == episode.id }) {
            selectedIndex = actualIndex
            
            audioPlayer.stopAudio()
            
            // Add a small delay to avoid audio conflicts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                audioPlayer.playEpisode(episode)
                PlayedEpisodesManager.shared.markAsPlayed(episode)
                if let feedUrl = selectedPodcast?.feedUrl {
                    PersistenceManager.saveLastPlayback(episode: episode, feedUrl: feedUrl)
                }
            }
        }
    }
    
    /// Toggles the inclusion of an episode in the play queue (cue).
    /// If the episode is already in the cue, it is removed; otherwise, it is added.
    /// The function also saves the updated cue to persistent storage.
    private func handleToggleCue(for episode: PodcastEpisode) {
        if let idx = cueList.firstIndex(where: { $0.id == episode.id }) {
            cueList.remove(at: idx)
        } else {
            var newEpisode = episode
            // Ensure the episode has an associated podcast name.
            // Always prefer the selectedPodcast title if available
            newEpisode.podcastName = selectedPodcast?.title ?? episode.podcastName
            
            // Generate a unique ID for the cue version of the episode.
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
            cueList.append(newEpisode)
        }
        let feedUrl = episode.feedUrl ?? selectedPodcast?.feedUrl
        PersistenceManager.saveCue(cueList, feedUrl: feedUrl)
        NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
    }
    
    /// Initiates the download process for the specified episode.
    private func handleDownload(episode: PodcastEpisode) {
        DownloadManager.shared.downloadEpisode(episode)
    }
    
    var body: some View {
        // Use the computed property instead of function call
        let sortedEpisodesList = sortedEpisodes
        let cueMembership = Set(cue.map { $0.url.absoluteString })
        let refreshToken = Int(lastRefreshTime.timeIntervalSince1970)
        
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Iterate over the sorted episodes
                ForEach(sortedEpisodesList) { episode in
                    // Use pre-computed index lookup
                    let originalIndex = episodeIndexMap[episode.id]
                    
                    let isPlaying = selectedIndex == originalIndex
                    
                    // Pre-compute expensive checks outside the view
                    let isInCue = cueMembership.contains(episode.url.absoluteString)
                    
                    let config = EpisodeRowConfiguration(
                        episode: episode,
                        index: originalIndex ?? -1,
                        isPlaying: isPlaying,
                        isInCue: isInCue,
                        // For the playing episode, use the current time from the audio player
                        currentTime: isPlaying ? audioPlayer.currentTime : 0,
                        // For the playing episode, use the duration from the audio player
                        duration: isPlaying ? audioPlayer.duration : (episode.duration ?? 0),
                        audioPlayer: audioPlayer,
                        selectedPodcast: selectedPodcast,
                        onSelect: { idx in handleEpisodeSelect(idx, episode: episode) },
                        onToggleCue: handleToggleCue,
                        onDownload: handleDownload
                    )
                    
                    // Render the episode row using the configured settings.
                    let rowIDBase = "\(episode.id)-\(isPlaying)-\(isInCue)"
                    let rowID = isPlaying ? "\(rowIDBase)-\(refreshToken)" : rowIDBase
                    ConfiguredEpisodeRow(config: config)
                        .id(rowID) // Only the playing row gets the refresh token to limit invalidations
                }
            }
            .padding(.top, 10)
            .padding() // Padding around the entire list.
        }
        // Force refresh the view periodically to update the time display
        .onReceive(refreshTimer) { _ in
            guard selectedIndex != nil else { return }
            lastRefreshTime = Date()
        }
        .onAppear {
            updateSortedCache()
        }
        .onChange(of: episodes.count) {
            updateSortedCache()
        }
        .onChange(of: selectedIndex) {
            updateSortedCache()
        }
        .focusable(false)
        .applyFocusEffectDisabled()
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

private extension EpisodeListView {
    var sortedEpisodes: [PodcastEpisode] {
        if sortedEpisodesCache.isEmpty && !episodes.isEmpty {
            return episodes
        }
        return sortedEpisodesCache
    }

    func updateSortedCache() {
        let newIds = episodes.map { $0.id }
        if newIds != cachedEpisodeIDs || sortedEpisodesCache.count != episodes.count {
            sortedEpisodesCache = episodes
            cachedEpisodeIDs = newIds
            episodeIndexMap = Dictionary(uniqueKeysWithValues: episodes.enumerated().map { ($0.element.id, $0.offset) })
        }
    }
}
