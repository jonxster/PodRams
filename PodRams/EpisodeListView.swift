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
    
    // Add a timer to force UI updates
    @State private var refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    /// Handles selection of an episode.
    /// Stops current playback, sets the new episode index, and starts playback with a slight delay.
    private func handleEpisodeSelect(_ index: Int, episode: PodcastEpisode) {
        // Reset cue playing state when selecting an episode from a podcast
        isCuePlaying = false
        
        // First stop any current playback
        audioPlayer.stopAudio()
        
        // Then set the new index and start playback
        selectedIndex = index
        
        // Get the local URL if available, otherwise use the remote URL
        let playURL = DownloadManager.shared.localURL(for: episode) ?? episode.url
        
        // Add a small delay to ensure the previous playback is fully stopped
        // Call playAudio directly (it now handles async loading)
        // Save last playback in a background task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { 
            audioPlayer.playAudio(url: playURL)
            // Move persistence saving to background task
            Task(priority: .background) { 
                PersistenceManager.saveLastPlayback(episode: episode, feedUrl: episode.feedUrl ?? "")
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Enumerate over episodes to generate a configured row for each.
                ForEach(Array(episodes.enumerated()), id: \.offset) { index, episode in
                    let isPlaying = selectedEpisodeIndex == index
                    let config = EpisodeRowConfiguration(
                        episode: episode,
                        index: index,
                        isPlaying: isPlaying,
                        isInCue: cue.contains { $0.url.absoluteString == episode.url.absoluteString },
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
                    ConfiguredEpisodeRow(config: config)
                }
            }
            .padding(.top, 10)
            .padding() // Padding around the entire list.
        }
        // Force refresh the view periodically to update the time display
        .onReceive(refreshTimer) { _ in
            // This empty handler forces the view to refresh
        }
    }
}
