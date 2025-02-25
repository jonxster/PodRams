//
//  EpisodeListView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// EpisodeListView.swift

import SwiftUI

struct EpisodeListView: View {
    var episodes: [PodcastEpisode]
    @Binding var selectedEpisodeIndex: Int?
    @ObservedObject var audioPlayer: AudioPlayer
    @Binding var cue: [PodcastEpisode]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Episodes (\(episodes.count))")
                .font(.headline)
                .padding(.horizontal)

            if episodes.isEmpty {
                ProgressView("Loading episodes...")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        episodeRow(for: episode, index: index)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .frame(minWidth: 250)
    }

    private func episodeRow(for episode: PodcastEpisode, index: Int) -> some View {
        let isPlaying = selectedEpisodeIndex == index

        return HStack(spacing: 8) {
            Text(episode.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isPlaying {
                playbackTimeDisplay()
            }

            Button(action: {
                toggleCue(for: episode)
            }) {
                Image(systemName: "list.bullet")
                    .foregroundColor(cueContains(episode) ? .green : .white)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEpisodeIndex = index
            audioPlayer.playAudio(url: episode.url)
            PersistenceManager.saveLastPlayback(episode: episode, feedUrl: episode.feedUrl ?? "")
        }
        .listRowInsets(EdgeInsets())
        .background(rowBackground(for: isPlaying))
    }

    private func rowBackground(for isPlaying: Bool) -> some View {
        Group {
            if isPlaying {
                EpisodeRowBackground(currentTime: audioPlayer.currentTime, duration: audioPlayer.duration)
            } else {
                Color(NSColor.clear)
            }
        }
    }

    private func playbackTimeDisplay() -> some View {
        Text("\(formatTime(audioPlayer.currentTime)) of \(formatTime(audioPlayer.duration))")
            .foregroundColor(.white.opacity(0.7))
            .font(.caption)
            .frame(width: 100, alignment: .trailing)
    }

    private func cueContains(_ episode: PodcastEpisode) -> Bool {
        cue.contains { $0.id == episode.id }
    }

    private func toggleCue(for episode: PodcastEpisode) {
        if let idx = cue.firstIndex(where: { $0.id == episode.id }) {
            cue.remove(at: idx)
        } else {
            cue.append(episode)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
