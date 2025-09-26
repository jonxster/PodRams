import SwiftUI
import Foundation

struct EpisodeRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Preview for a non-playing episode
            EpisodeRow(
                episode: PodcastEpisode(
                    title: "Test Episode",
                    url: URL(string: "https://example.com/test.mp3")!,
                    artworkURL: nil,
                    duration: 300,
                    showNotes: nil
                ),
                isPlaying: false,
                isInCue: false,
                currentTime: 0,
                duration: 300,
                audioPlayer: AudioPlayer(),
                onSeek: { _ in },
                onSelect: { },
                onToggleCue: { }
            )
            
            // Preview for a playing episode
            EpisodeRow(
                episode: PodcastEpisode(
                    title: "Currently Playing Episode",
                    url: URL(string: "https://example.com/playing.mp3")!,
                    artworkURL: nil,
                    duration: 300,
                    showNotes: nil
                ),
                isPlaying: true,
                isInCue: true,
                currentTime: 150,
                duration: 300,
                audioPlayer: AudioPlayer(),
                onSeek: { _ in },
                onSelect: { },
                onToggleCue: { }
            )
        }
        .padding()
        .background(AppTheme.background.tint(.clear, ))
        .previewLayout(.fixed(width: 500, height: 200))
    }
} 
