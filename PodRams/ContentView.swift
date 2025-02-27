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
    
    var currentPlayingTitle: some View {
        if let currentEpisode = activeEpisodes.indices.contains(selectedEpisodeIndex ?? -1) ? activeEpisodes[selectedEpisodeIndex!] : nil {
            return AnyView(
                HStack {
                    Spacer()
                    if isCuePlaying {
                        Button(action: {
                            isCueVisible.toggle()
                        }) {
                            Text("\(currentEpisode.podcastName ?? "Unknown Podcast")")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    } else {
                        Text(selectedPodcast?.title ?? "Unknown Podcast")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            )
        }
        return AnyView(EmptyView())
    }
    
    var body: some View {
        VStack(spacing: 12) {  // Increased spacing from 0 to 12
            // Player controls section
            PlayerView(
                audioPlayer: audioPlayer,
                episodes: activeEpisodes,
                currentEpisodeIndex: $selectedEpisodeIndex,
                feedArtworkURL: isCuePlaying ? nil : selectedPodcast?.feedArtworkURL
            )
            .padding(.bottom, 12)  // Increased from 8 to 12
            
            // Title section with clear separation
            currentPlayingTitle
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)  // Added explicit vertical padding
            //              .background(Color.gray.opacity(0.1))
            
            // Episode list section
            ZStack {
                if !activeEpisodes.isEmpty {
                    EpisodeListView(
                        episodes: activeEpisodes,
                        selectedEpisodeIndex: selectedEpisodeIndex,
                        cue: cue,
                        audioPlayer: audioPlayer,
                        selectedPodcast: selectedPodcast,
                        selectedIndex: $selectedEpisodeIndex,
                        cueList: $cue
                    )
                } else {
                    Text("No episodes available")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                if isPodcastLoading {
                    ProgressView("Loading podcast...")
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .frame(maxHeight: .infinity)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddTestPodcast"))) { notification in
            if let testPodcast = notification.userInfo?["podcast"] as? Podcast {
                subscribedPodcasts.append(testPodcast)
                selectedPodcast = testPodcast
                selectedEpisodeIndex = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddTestEpisode"))) { notification in
            if let testEpisode = notification.userInfo?["episode"] as? PodcastEpisode {
                cue.append(testEpisode)
                isCuePlaying = true
                selectedEpisodeIndex = cue.count - 1
            }
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: { isAudioOutputSelectionVisible.toggle() }) {
                Image(systemName: AudioOutputManager.shared.currentRouteIcon)
            }
            .popover(isPresented: $isAudioOutputSelectionVisible) {
                AudioOutputSelectionView()
            }
            
            Button(action: { isSubscribeVisible = true }) {
                Image(systemName: "rectangle.and.paperclip")
            }
            .popover(isPresented: $isSubscribeVisible) {
                SubscribeView(
                    subscribedPodcasts: $subscribedPodcasts,
                    selectedPodcast: $selectedPodcast,
                    podcastFetcher: podcastFetcher,
                    audioPlayer: audioPlayer
                )
            }
            
            Button(action: { isSettingsVisible = true }) {
                Image(systemName: "gear")
            }
            .popover(isPresented: $isSettingsVisible) {
                SettingsView()
            }
            
            Button(action: { isFavoritesVisible = true }) {
                Image(systemName: "star")
            }
            .disabled(favoritePodcasts.isEmpty)
            .help("Favorites (\(favoritePodcasts.count))")
            
            Button(action: { if !cue.isEmpty { isCueVisible.toggle() } }) {
                Image(systemName: "list.bullet")
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
    @State var isHovering = false
    
    var body: some View {
        HStack(spacing: 0) {
            if isPlaying {
                Image(systemName: "speaker.3.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .padding(.trailing, 10)
            } else if isHovering {
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .padding(.trailing, 10)
            } else {
                Spacer()
                    .frame(width: 26) // 16 + 10 for consistent spacing
            }
            
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
                            .background(Color.clear)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
            .onHover { hovering in
                isHovering = hovering
            }
            
            if isInCue {
                Image(systemName: "music.note.list")
                    .foregroundColor(.blue)
                    .frame(width: 40)
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .onTapGesture {
                        onToggleCue?()
                    }
            }
            
            DownloadButton(episode: episode)
                .frame(width: 40)
                .padding(.trailing, 8)
        }
    }
}
