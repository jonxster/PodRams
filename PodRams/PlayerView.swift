//
//  PlayerView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// PlayerView.swift

import SwiftUI

struct PlayerView: View {
    @ObservedObject var audioPlayer: AudioPlayer
    var episodes: [PodcastEpisode]
    @Binding var currentEpisodeIndex: Int?
    
    /// Fallback image if the episode lacks artwork.
    var feedArtworkURL: URL?
    
    /// Controls whether to show the front (artwork) or back (show notes).
    @State private var isFlipped = false
    
    var currentEpisode: PodcastEpisode? {
        guard let idx = currentEpisodeIndex, idx >= 0, idx < episodes.count else { return nil }
        return episodes[idx]
    }
    
    var body: some View {
        VStack {
            Text(currentEpisode?.title ?? "Select an Episode")
                .font(.title2)
                .padding()
            
            ZStack {
                frontSide
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 0 : 1)
                
                backSide
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 1 : 0)
            }
            .animation(.default, value: isFlipped)
            .frame(width: 220, height: 220)
            .onTapGesture {
                withAnimation { isFlipped.toggle() }
            }
            
            // Removed audio output icon from here.
            controlButtons
            volumeControls
        }
        .frame(minHeight: 300)
    }
    
    private var frontSide: some View {
        Group {
            if audioPlayer.isLoading {
                ProgressView()
            } else if let artworkURL = currentEpisode?.artworkURL ?? feedArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo").resizable().scaledToFit().foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "music.note").resizable().scaledToFit().foregroundColor(.gray)
            }
        }
        .cornerRadius(8)
        .frame(width: 220, height: 220)
    }
    
    private var backSide: some View {
        let notes = currentEpisode?.showNotes ?? "No show notes"
        return ScrollView {
            Text(notes)
                .padding()
                .multilineTextAlignment(.leading)
        }
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
        .frame(width: 220, height: 220)
    }
    
    private var controlButtons: some View {
        HStack(spacing: 40) {
            Button(action: { playPrevious() }) {
                Image(systemName: "backward.fill").font(.system(size: 36))
            }
            .buttonStyle(.plain)
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == 0)
            
            Button(action: {
                if let ep = currentEpisode {
                    if audioPlayer.isPlaying {
                        audioPlayer.pauseAudio()
                    } else {
                        audioPlayer.playAudio(url: ep.url)
                    }
                }
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36))
            }
            .buttonStyle(.plain)
            .disabled(currentEpisode == nil)
            
            Button(action: { audioPlayer.stopAudio() }) {
                Image(systemName: "stop.fill").font(.system(size: 36))
            }
            .buttonStyle(.plain)
            .disabled(currentEpisode == nil)
            
            Button(action: { playNext() }) {
                Image(systemName: "forward.fill").font(.system(size: 36))
            }
            .buttonStyle(.plain)
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == episodes.count - 1)
        }
        .padding()
    }
    
    private var volumeControls: some View {
        HStack {
            Button(action: { audioPlayer.volume = 0 }) {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.white)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            
            Slider(value: $audioPlayer.volume, in: 0...1)
                .frame(maxWidth: 200)
            
            Button(action: { audioPlayer.volume = 1 }) {
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.white)
            }
            .buttonStyle(.borderless)
            .focusable(false)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
    
    private func playPrevious() {
        guard let idx = currentEpisodeIndex, idx > 0 else { return }
        currentEpisodeIndex = idx - 1
        if let episode = currentEpisode {
            audioPlayer.playAudio(url: episode.url)
        }
    }
    
    private func playNext() {
        guard let idx = currentEpisodeIndex, idx < episodes.count - 1 else { return }
        currentEpisodeIndex = idx + 1
        if let episode = currentEpisode {
            audioPlayer.playAudio(url: episode.url)
        }
    }
}
