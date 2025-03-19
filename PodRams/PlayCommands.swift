import SwiftUI

/// Provides a set of player control commands accessible via the app's menu.
/// Includes commands for playback control and navigation.
struct PlayCommands: Commands {
    @ObservedObject var audioPlayer: AudioPlayer
    @Binding var currentEpisodeIndex: Int?
    var episodes: [PodcastEpisode]
    
    // Store previous volume when muting
    @State private var previousVolume: Double = 1.0
    
    var body: some Commands {
        // The "Play" command menu contains playback control options
        CommandMenu("Play") {
            // Play/Pause toggle
            Button(audioPlayer.isPlaying ? "Pause" : "Play") {
                if audioPlayer.isPlaying {
                    audioPlayer.pauseAudio()
                } else if let index = currentEpisodeIndex, index < episodes.count {
                    audioPlayer.playAudio(url: episodes[index].url)
                }
            }
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(currentEpisodeIndex == nil)
            
            // Stop playback
            Button("Stop") {
                audioPlayer.stopAudio()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(currentEpisodeIndex == nil)
            
            Divider()
            
            // Previous episode
            Button("Previous Episode") {
                if let index = currentEpisodeIndex, index > 0 {
                    let newIndex = index - 1
                    currentEpisodeIndex = newIndex
                    audioPlayer.playAudio(url: episodes[newIndex].url)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == 0)
            
            // Next episode
            Button("Next Episode") {
                if let index = currentEpisodeIndex, index < episodes.count - 1 {
                    let newIndex = index + 1
                    currentEpisodeIndex = newIndex
                    audioPlayer.playAudio(url: episodes[newIndex].url)
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .disabled(currentEpisodeIndex == nil || currentEpisodeIndex == episodes.count - 1)
            
            Divider()
            
            // Skip backward 30 seconds
            Button("Skip Backward 30 Seconds") {
                let newTime = max(0, audioPlayer.currentTime - 30)
                audioPlayer.seek(to: newTime)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(currentEpisodeIndex == nil)
            
            // Skip forward 30 seconds
            Button("Skip Forward 30 Seconds") {
                let newTime = min(audioPlayer.duration, audioPlayer.currentTime + 30)
                audioPlayer.seek(to: newTime)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(currentEpisodeIndex == nil)
            
            Divider()
            
            // Volume controls
            Button("Volume Up") {
                audioPlayer.volume = min(1.0, audioPlayer.volume + 0.1)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            
            Button("Volume Down") {
                audioPlayer.volume = max(0.0, audioPlayer.volume - 0.1)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            
            Button("Mute/Unmute") {
                if audioPlayer.volume > 0 {
                    // If volume is not 0, we're muting
                    previousVolume = audioPlayer.volume
                    audioPlayer.volume = 0
                } else {
                    // If volume is 0, restore previous volume
                    audioPlayer.volume = previousVolume
                }
            }
            .keyboardShortcut("m", modifiers: [.command])
        }
    }
} 