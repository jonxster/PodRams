import SwiftUI

struct ContentView: View {
    @StateObject var podcastFetcher = PodcastFetcher()
    @StateObject var audioPlayer = AudioPlayer()

    @State private var favoritePodcasts: [Podcast] = []
    @State private var cue: [PodcastEpisode] = []
    @State private var subscribedPodcasts: [Podcast] = []
    @State private var lastPlayedEpisode: PodcastEpisode? = nil

    @State private var selectedPodcast: Podcast?
    @State private var selectedEpisodeIndex: Int?

    @State private var isCuePlaying = false
    @State private var isSearching = false
    @State private var isCueVisible = false
    @State private var isFavoritesVisible = false
    @State private var isPodcastLoading = false
    @State private var isAudioOutputSelectionVisible = false
    @State private var isSubscribeVisible = false
    @State private var isSettingsVisible = false

    var activeEpisodes: [PodcastEpisode] {
        if isCuePlaying {
            return cue
        } else if let p = selectedPodcast {
            return p.episodes
        }
        return []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            PlayerView(
                audioPlayer: audioPlayer,
                episodes: activeEpisodes,
                currentEpisodeIndex: $selectedEpisodeIndex,
                feedArtworkURL: isCuePlaying ? nil : selectedPodcast?.feedArtworkURL
            )
            .padding(.bottom, 20)
            
            ZStack {
                if !activeEpisodes.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(activeEpisodes.enumerated()), id: \.element.id) { index, episode in
                                EpisodeRow(
                                    episode: episode,
                                    isPlaying: selectedEpisodeIndex == index,
                                    isInCue: cue.contains { $0.id == episode.id },
                                    currentTime: selectedEpisodeIndex == index ? audioPlayer.currentTime : 0,
                                    duration: selectedEpisodeIndex == index ? audioPlayer.duration : 0,
                                    onSeek: { newTime in
                                        audioPlayer.seek(to: newTime)
                                    },
                                    onSelect: {
                                        selectedEpisodeIndex = index
                                        let playURL = DownloadManager.shared.localURL(for: episode) ?? episode.url
                                        audioPlayer.playAudio(url: playURL)
                                        PersistenceManager.saveLastPlayback(episode: episode, feedUrl: episode.feedUrl ?? "")
                                    },
                                    onToggleCue: {
                                        if let idx = cue.firstIndex(where: { $0.id == episode.id }) {
                                            cue.remove(at: idx)
                                        } else {
                                            var newEpisode = episode
                                            newEpisode.podcastName = selectedPodcast?.title
                                            cue.append(newEpisode)
                                        }
                                    },
                                    onDownload: {
                                        DownloadManager.shared.downloadEpisode(episode)
                                    }
                                )
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.top, 10)
                        .padding()
                    }
                } else {
                    Text("No episodes available")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if isPodcastLoading {
                    ProgressView("Loading podcast...")
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { toolbarContent }
        .popover(isPresented: $isSearching) {
            SearchSheetView(
                podcastFetcher: podcastFetcher,
                selectedPodcast: $selectedPodcast,
                selectedEpisodeIndex: $selectedEpisodeIndex,
                audioPlayer: audioPlayer,
                isCuePlaying: $isCuePlaying,
                favoritePodcasts: $favoritePodcasts,
                subscribedPodcasts: $subscribedPodcasts
            ) {
                isSearching = false
            }
            .frame(minWidth: 400, minHeight: 500)
        }
        .popover(isPresented: $isCueVisible) {
            CueSheetView(
                cue: $cue,
                isCuePlaying: $isCuePlaying,
                selectedEpisodeIndex: $selectedEpisodeIndex,
                audioPlayer: audioPlayer
            )
            .frame(minWidth: 400, minHeight: 500)
        }
        .popover(isPresented: $isFavoritesVisible) {
            FavoritesView(
                favoritePodcasts: $favoritePodcasts,
                selectedPodcast: $selectedPodcast,
                selectedEpisodeIndex: $selectedEpisodeIndex,
                audioPlayer: audioPlayer,
                podcastFetcher: podcastFetcher
            )
            .onDisappear {
                PersistenceManager.saveFavorites(favoritePodcasts)
            }
            .frame(minWidth: 400, minHeight: 500)
        }
        .background(KeyboardShortcutView { key in
            switch key {
            case .space:
                togglePlayPause()
            case .commandF:
                isSearching.toggle()
            case .commandC:
                if !cue.isEmpty { isCueVisible.toggle() }
            }
        })
        .task {
            favoritePodcasts = await PersistenceManager.loadFavorites()
            cue = await PersistenceManager.loadCue()
            subscribedPodcasts = await PersistenceManager.loadSubscriptions()
            lastPlayedEpisode = await PersistenceManager.loadLastPlayback()
            if let lastEp = lastPlayedEpisode,
               let feedUrl = lastEp.feedUrl, !feedUrl.isEmpty {
                let cachedPodcast = Podcast(title: lastEp.title, feedUrl: feedUrl, episodes: [lastEp])
                cachedPodcast.feedArtworkURL = lastEp.artworkURL
                selectedPodcast = cachedPodcast
                selectedEpisodeIndex = 0
                audioPlayer.playAudio(url: lastEp.url)
                isPodcastLoading = true
                Task {
                    let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: cachedPodcast)
                    await MainActor.run {
                        cachedPodcast.episodes = episodes
                        if let feedArt = feedArt {
                            cachedPodcast.feedArtworkURL = feedArt
                        }
                        selectedPodcast = cachedPodcast
                        if let index = episodes.firstIndex(where: { $0.url == lastEp.url }) {
                            selectedEpisodeIndex = index
                        } else {
                            selectedEpisodeIndex = 0
                        }
                        isPodcastLoading = false
                    }
                }
            }
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: { isAudioOutputSelectionVisible.toggle() }) {
                Image(systemName: "airplayaudio")
                    .foregroundColor(.white)
            }
            .popover(isPresented: $isAudioOutputSelectionVisible) {
                AudioOutputSelectionView()
            }
            
            Button(action: { isSubscribeVisible = true }) {
                Image(systemName: "rectangle.and.paperclip")
                    .foregroundColor(subscribedPodcasts.isEmpty ? .gray : .white)
            }
            .popover(isPresented: $isSubscribeVisible) {
                SubscribeView(
                    subscribedPodcasts: $subscribedPodcasts,
                    selectedPodcast: $selectedPodcast,
                    podcastFetcher: podcastFetcher,
                    audioPlayer: audioPlayer
                )
                .onDisappear {
                    PersistenceManager.saveSubscriptions(subscribedPodcasts)
                }
                .frame(minWidth: 400, minHeight: 500)
            }
            
            Button(action: { isSettingsVisible = true }) {
                Image(systemName: "gear")
            }
            .popover(isPresented: $isSettingsVisible) {
                SettingsView()
            }
            
            Button(action: { isFavoritesVisible = true }) {
                Image(systemName: "star")
                    .foregroundColor(favoritePodcasts.isEmpty ? .gray : .white)
            }
            .disabled(favoritePodcasts.isEmpty)
            .help("Favorites (\(favoritePodcasts.count))")
            
            Button(action: { if !cue.isEmpty { isCueVisible.toggle() } }) {
                Image(systemName: "list.bullet")
                    .foregroundColor(cue.isEmpty ? .gray : .white)
            }
            .disabled(cue.isEmpty)
            .help("Cue (\(cue.count))")
            
            Button(action: { isSearching.toggle() }) {
                Image(systemName: "magnifyingglass")
            }
            .help("Search for Podcasts")
        }
    }
    
    private func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pauseAudio()
        } else if let index = selectedEpisodeIndex, index < activeEpisodes.count {
            audioPlayer.playAudio(url: activeEpisodes[index].url)
        }
    }
}

struct EpisodeRow: View {
    let episode: PodcastEpisode
    let isPlaying: Bool
    let isInCue: Bool
    let currentTime: Double
    let duration: Double
    var onSeek: ((Double) -> Void)?
    var onSelect: (() -> Void)?
    var onToggleCue: (() -> Void)?
    var onDownload: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                onSelect?()
            }) {
                ZStack(alignment: .leading) {
                    ProgressBarView(currentTime: currentTime, duration: duration, onSeek: { newTime in
                        onSeek?(newTime)
                    })
                    .padding(.trailing, 80)
                    
                    HStack {
                        Text(episode.title)
                            .lineLimit(1)
                            .foregroundColor(isPlaying ? .white : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Updated playlist icon section
            Image(systemName: "music.note.list")
                .foregroundColor(isInCue ? .green : .blue)
                .frame(width: 40)
                .padding(.trailing, 8)
                .onTapGesture {
                    onToggleCue?()
                }
            
            DownloadButton(episode: episode)
                .frame(width: 40)
                .padding(.trailing, 8)
        }
    }
}
