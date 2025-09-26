#if DEBUG
import SwiftUI

@MainActor
private struct PreviewSeed {
    let podcast: Podcast
    let cueEpisodes: [PodcastEpisode]

    static func make() -> PreviewSeed {
        let episodes: [PodcastEpisode] = [
            PodcastEpisode(
                title: "Morning News Update",
                url: URL(string: "https://example.com/audio/morning-news.mp3")!,
                artworkURL: URL(string: "https://example.com/artwork/morning.png"),
                duration: 1_200,
                showNotes: "All the top stories you need to know to start the day.",
                feedUrl: "https://example.com/feed",
                podcastName: "Daily Swift Radio"
            ),
            PodcastEpisode(
                title: "Interview with a Swift Expert",
                url: URL(string: "https://example.com/audio/swift-interview.mp3")!,
                artworkURL: URL(string: "https://example.com/artwork/interview.png"),
                duration: 2_400,
                showNotes: "Deep dive into SwiftUI best practices.",
                feedUrl: "https://example.com/feed",
                podcastName: "Daily Swift Radio"
            ),
            PodcastEpisode(
                title: "Community Highlights",
                url: URL(string: "https://example.com/audio/community.mp3")!,
                artworkURL: URL(string: "https://example.com/artwork/community.png"),
                duration: 1_500,
                showNotes: "What the Swift community built this week.",
                feedUrl: "https://example.com/feed",
                podcastName: "Daily Swift Radio"
            )
        ]

        let podcast = Podcast(title: "Daily Swift Radio", feedUrl: "https://example.com/feed", episodes: episodes)
        podcast.feedArtworkURL = URL(string: "https://example.com/artwork/show.png")

        return PreviewSeed(podcast: podcast, cueEpisodes: Array(episodes.prefix(2)))
    }
}

@MainActor
struct ContentViewPreviewContainer: View {
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var appEpisodes: [PodcastEpisode]
    @State private var appSelectedEpisodeIndex: Int?
    @State private var appSelectedPodcast: Podcast?
    private let initialState: ContentView.InitialState

    init() {
        let seed = PreviewSeed.make()
        _appEpisodes = State(initialValue: seed.podcast.episodes)
        _appSelectedEpisodeIndex = State(initialValue: 0)
        _appSelectedPodcast = State(initialValue: seed.podcast)
        initialState = ContentView.InitialState(
            favoritePodcasts: [seed.podcast],
            cue: seed.cueEpisodes,
            subscribedPodcasts: [seed.podcast],
            lastPlayedEpisode: seed.podcast.episodes.first,
            selectedPodcast: seed.podcast,
            selectedEpisodeIndex: 0,
            isCuePlaying: false,
            isInitialized: true
        )
    }

    var body: some View {
        ContentView(
            appEpisodes: $appEpisodes,
            appCurrentEpisodeIndex: $appSelectedEpisodeIndex,
            appSelectedPodcast: $appSelectedPodcast,
            initialState: initialState
        )
        .environmentObject(audioPlayer)
    }
}

#Preview("Main App Preview") {
    ContentViewPreviewContainer()
        .frame(minWidth: 900, minHeight: 600)
}
#endif
