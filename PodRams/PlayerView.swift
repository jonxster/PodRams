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
    @Namespace private var playerGlassNamespace
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVolumeExpanded = false
    
    /// Fallback image if the episode lacks artwork.
    var feedArtworkURL: URL?
    
    var currentEpisode: PodcastEpisode? {
        guard let idx = currentEpisodeIndex, idx >= 0, idx < episodes.count else { return nil }
        return episodes[idx]
    }
    
    var body: some View {
        VStack(spacing: 16) {
            frontSide
                .padding(.top, 24)
                .compatGlassEffectUnion(id: "player-artwork", namespace: playerGlassNamespace)

            if let episode = currentEpisode {
                Text(episode.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
            } else {
                Text("Select an Episode")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.secondaryText)
                    .padding(.horizontal, 24)
            }

            controlButtons
                .compatGlassEffectUnion(id: "player-controls", namespace: playerGlassNamespace)

            ProgressBarView(
                currentTime: audioPlayer.currentTime,
                duration: audioPlayer.duration,
                chapters: audioPlayer.currentEpisode?.chapters ?? [],
                onSeek: { newTime in audioPlayer.seek(to: newTime) },
                showLabel: false
            )
            .frame(width: 220)
        }
        .frame(minHeight: 320)
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
                    width: 260,
                    height: 260
                )
            } else {
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(width: 260, height: 260)
        .compatBackgroundExtensionEffect()
        .compatGlassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .compatGlassEffectID("player-card", in: playerGlassNamespace)
    }

    private var controlButtons: some View {
        let bubbleWidth: CGFloat = 360

        return HStack(spacing: 28) {
            volumeToggle

            ZStack {
                transportButtons
                    .opacity(isVolumeExpanded ? 0 : 1)
                    .allowsHitTesting(!isVolumeExpanded)

                if isVolumeExpanded {
                    VolumeSliderView(volume: $audioPlayer.volume)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(width: bubbleWidth)
        .background(
            Capsule(style: .continuous)
                .fill(bubbleFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(bubbleStroke, lineWidth: 1.0)
                )
                .shadow(color: bubbleShadow, radius: 10, x: 0, y: 6)
        )
        .contentShape(Capsule(style: .continuous))
        .compatGlassEffectUnion(id: "transport-cluster", namespace: playerGlassNamespace)
        .buttonStyle(.plain)
        .onHover { hovering in
            if !hovering && isVolumeExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVolumeExpanded = false
                }
            }
        }
    }

    private var volumeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVolumeExpanded.toggle()
            }
        } label: {
            Image(systemName: volumeIconName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
                .padding(4)
        }
        .help(LocalizedStringKey("Mute/Unmute"))
        .applyFocusEffectDisabled()
        .buttonStyle(.plain)
    }

    private var volumeIconName: String {
        if audioPlayer.volume <= 0.01 { return "speaker.slash.fill" }
        if audioPlayer.volume < 0.5 { return "speaker.wave.1.fill" }
        if audioPlayer.volume < 0.9 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var transportButtons: some View {
        HStack(spacing: 24) {
            Button(action: { playPrevious() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
            }
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == 0)
            .help(LocalizedStringKey("Previous Episode"))
            .applyFocusEffectDisabled()
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button(action: {
                if audioPlayer.isPlaying {
                    audioPlayer.pauseAudio()
                } else {
                    if let index = currentEpisodeIndex, index < episodes.count {
                        let episode = episodes[index]
                        audioPlayer.playEpisode(episode)
                    }
                }
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(playIconColor)
                    .id("play-button-\(audioPlayer.isPlaying)-\(UUID())")
            }
            .disabled(currentEpisode == nil)
            .help(audioPlayer.isPlaying ? LocalizedStringKey("Pause") : LocalizedStringKey("Play"))
            .applyFocusEffectDisabled()
            .keyboardShortcut(.space, modifiers: [])

            Button(action: { playNext() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
            }
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == episodes.count - 1)
            .help(LocalizedStringKey("Next Episode"))
            .applyFocusEffectDisabled()
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(x: -32)
    }

    private var bubbleFill: Color {
        AppTheme.color(.surface, in: themeMode)
    }

    private var bubbleStroke: Color {
        AppTheme.color(.secondaryText, in: themeMode).opacity(colorScheme == .dark ? 0.25 : 0.12)
    }

    private var bubbleShadow: Color {
        colorScheme == .dark
            ? AppTheme.color(.background, in: .dark).opacity(0.45)
            : AppTheme.color(.secondaryText, in: .light).opacity(0.18)
    }

    private var themeMode: AppTheme.Mode {
        colorScheme == .dark ? .dark : .light
    }

    private var playIconColor: Color {
        colorScheme == .dark ? AppTheme.accent : AppTheme.primaryText
    }

    private func playPrevious() {
        guard let idx = currentEpisodeIndex, idx > 0 else { return }
        currentEpisodeIndex = idx - 1
        if let episode = currentEpisode {
            audioPlayer.playEpisode(episode)
        }
    }
 
    private func playNext() {
        guard let idx = currentEpisodeIndex, idx < episodes.count - 1 else { return }
        currentEpisodeIndex = idx + 1
        if let episode = currentEpisode {
            audioPlayer.playEpisode(episode)
        }
    }
}

private struct VolumeSliderView: View {
    @Binding var volume: Double

    var body: some View {
        Slider(value: $volume, in: 0...1)
            .tint(AppTheme.accent)
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
