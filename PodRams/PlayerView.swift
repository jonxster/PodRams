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
    
    // Add state to track loaded show notes and loading state
    @State private var loadedShowNotes: String = "Loading show notes..."
    @State private var isLoadingNotes = false
    
    var currentEpisode: PodcastEpisode? {
        guard let idx = currentEpisodeIndex, idx >= 0, idx < episodes.count else { return nil }
        return episodes[idx]
    }
    
    var body: some View {
        VStack {
            Text(currentEpisode?.title ?? "Select an Episode")
                .font(.title3)
                .padding(.vertical, 4)
            
            ZStack {
                // Front side: always built for quick display
                frontSide
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 0 : 1)
                // Back side: build only when flipped to avoid initial layout cost
                Group {
                    if isFlipped {
                        backSide
                    }
                }
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
            }
            .animation(.default, value: isFlipped)
            .frame(width: 180, height: 180)
            .onTapGesture {
                withAnimation { 
                    isFlipped.toggle() 
                    // Load notes when flipped to back
                    if isFlipped && !isLoadingNotes {
                        loadShowNotes()
                    }
                }
            }
            
            // Removed audio output icon from here.
            controlButtons
            volumeControls
        }
        .frame(minHeight: 260)
    }
    
    private var frontSide: some View {
        Group {
            if audioPlayer.isLoading {
                LoadingIndicator()
                    .frame(width: 32, height: 32)
            } else if let artworkURL = currentEpisode?.artworkURL ?? feedArtworkURL {
                // Use cached async image loading to avoid main-thread delays
                CachedAsyncImage(
                    url: artworkURL,
                    width: 180,
                    height: 180
                )
            } else {
                Image(systemName: "music.note").resizable().scaledToFit().foregroundColor(.gray)
            }
        }
        .cornerRadius(8)
        .frame(width: 180, height: 180)
    }
    
    private var backSide: some View {
        ScrollView {
            Text(loadedShowNotes)
                .padding()
                .multilineTextAlignment(.leading)
        }
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
        .frame(width: 180, height: 180)
    }
    
    private func loadShowNotes() {
        guard let episode = currentEpisode, !isLoadingNotes else { return }
        
        isLoadingNotes = true
        
        // Use background thread for processing
        DispatchQueue.global(qos: .userInitiated).async {
            let notes: String
            
            if let showNotes = episode.showNotes, !showNotes.isEmpty {
                // Process on background thread to avoid UI blocking
                notes = showNotes.htmlStripped
            } else {
                notes = "No show notes available"
            }
            
            // Return to main thread for UI update
            DispatchQueue.main.async {
                loadedShowNotes = notes
                isLoadingNotes = false
            }
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 30) {
            Button(action: { playPrevious() }) {
                Image(systemName: "backward.fill").font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == 0)
            
            Button(action: {
                if audioPlayer.isPlaying {
                    audioPlayer.pauseAudio()
                } else {
                    if let index = currentEpisodeIndex, index < episodes.count {
                        audioPlayer.playAudio(url: episodes[index].url)
                    }
                }
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .id("play-button-\(audioPlayer.isPlaying)-\(UUID())") // Force redraw with unique ID
            }
            .buttonStyle(.plain)
            .disabled(currentEpisode == nil)
            
            Button(action: { audioPlayer.stopAudio() }) {
                Image(systemName: "stop.fill").font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .disabled(currentEpisode == nil)
            
            Button(action: { playNext() }) {
                Image(systemName: "forward.fill").font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == episodes.count - 1)
        }
        .padding(.vertical, 8)
    }
    
    private var volumeControls: some View {
        HStack {
            Button(action: { audioPlayer.volume = 0 }) {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .focusable(false)
            
            Slider(value: $audioPlayer.volume, in: 0...1)
                .frame(maxWidth: 160)
            
            Button(action: { audioPlayer.volume = 1 }) {
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .focusable(false)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
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

// Add a helper struct for lazy loading content
struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}
