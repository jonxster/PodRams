//
//  EpisodeListView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// EpisodeListView.swift

import SwiftUI

// Helper view to handle a single episode row configuration
struct EpisodeRowConfiguration {
    let episode: PodcastEpisode
    let index: Int
    let isPlaying: Bool
    let isInCue: Bool
    let currentTime: Double
    let duration: Double
    let audioPlayer: AudioPlayer
    let selectedPodcast: Podcast?
    let onSelect: (Int) -> Void
    let onToggleCue: (PodcastEpisode) -> Void
    let onDownload: (PodcastEpisode) -> Void
}

// Separate view for episode rows
struct ConfiguredEpisodeRow: View {
    let config: EpisodeRowConfiguration
    
    var body: some View {
        EpisodeRow(
            episode: config.episode,
            isPlaying: config.isPlaying,
            isInCue: config.isInCue,
            currentTime: config.currentTime,
            duration: config.duration,
            onSeek: { newTime in
                config.audioPlayer.seek(to: newTime)
            },
            onSelect: {
                config.onSelect(config.index)
            },
            onToggleCue: {
                config.onToggleCue(config.episode)
            },
            onDownload: {
                config.onDownload(config.episode)
            }
        )
        .contentShape(Rectangle())
    }
}

struct EpisodeListView: View {
    let episodes: [PodcastEpisode]
    let selectedEpisodeIndex: Int?
    let cue: [PodcastEpisode]
    let audioPlayer: AudioPlayer
    let selectedPodcast: Podcast?
    @Binding var selectedIndex: Int?
    @Binding var cueList: [PodcastEpisode]
    
    private func handleEpisodeSelect(_ index: Int, episode: PodcastEpisode) {
        // First stop any current playback
        audioPlayer.stopAudio()
        
        // Then set the new index and start playback
        selectedIndex = index
        
        // Get the local URL if available, otherwise use the remote URL
        let playURL = DownloadManager.shared.localURL(for: episode) ?? episode.url
        
        // Add a small delay to ensure the previous playback is fully stopped
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            audioPlayer.playAudio(url: playURL)
            PersistenceManager.saveLastPlayback(episode: episode, feedUrl: episode.feedUrl ?? "")
        }
    }
    
    private func handleToggleCue(for episode: PodcastEpisode) {
        if let idx = cueList.firstIndex(where: { $0.id == episode.id }) {
            cueList.remove(at: idx)
        } else {
            var newEpisode = episode
            if newEpisode.podcastName == nil {
                newEpisode.podcastName = selectedPodcast?.title ?? episode.podcastName
            }
            // Create a unique ID for the cue version of the episode
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
    }
    
    private func handleDownload(episode: PodcastEpisode) {
        DownloadManager.shared.downloadEpisode(episode)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(episodes.enumerated()), id: \.offset) { index, episode in
                    let config = EpisodeRowConfiguration(
                        episode: episode,
                        index: index,
                        isPlaying: selectedEpisodeIndex == index,
                        isInCue: cue.contains { $0.url.absoluteString == episode.url.absoluteString },
                        currentTime: selectedEpisodeIndex == index ? audioPlayer.currentTime : 0,
                        duration: selectedEpisodeIndex == index ? audioPlayer.duration : 0,
                        audioPlayer: audioPlayer,
                        selectedPodcast: selectedPodcast,
                        onSelect: { idx in handleEpisodeSelect(idx, episode: episode) },
                        onToggleCue: handleToggleCue,
                        onDownload: handleDownload
                    )
                    
                    ConfiguredEpisodeRow(config: config)
                }
            }
            .padding(.top, 10)
            .padding()
        }
    }
}
