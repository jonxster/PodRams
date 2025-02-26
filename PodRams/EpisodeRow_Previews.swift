import SwiftUI
import Foundation

#Preview {
    VStack(spacing: 20) {
        // Normal state
        EpisodeRow(
            episode: PodcastEpisode(
                title: "Test Episode 1",
                url: URL(string: "https://example.com/1.mp3")!,
                artworkURL: nil,
                duration: 300,
                showNotes: nil,
                feedUrl: nil
            ),
            isPlaying: false,
            isInCue: false,
            currentTime: 0,
            duration: 300
        )
        
        // Playing state
        EpisodeRow(
            episode: PodcastEpisode(
                title: "Test Episode 2",
                url: URL(string: "https://example.com/2.mp3")!,
                artworkURL: nil,
                duration: 300,
                showNotes: nil,
                feedUrl: nil
            ),
            isPlaying: true,
            isInCue: false,
            currentTime: 150,
            duration: 300
        )
    }
    .frame(width: 400)
    .padding()
} 