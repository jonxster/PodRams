import SwiftUI
import Combine

/// Main content view for the podcast app.
/// Combines podcast fetching, audio playback, and various UI states.
struct ContentView: View {
    /// Fetches podcast data asynchronously.
    @StateObject var podcastFetcher = PodcastFetcher()
    /// Manages audio playback and related state.
    @StateObject var audioPlayer = AudioPlayer()
    
    /// User's list of favorite podcasts.
    @State private var favoritePodcasts: [Podcast] = []
    /// List of episodes in the cue (play queue).
    @State private var cue: [PodcastEpisode] = []
    /// User's list of subscribed podcasts.
    @State private var subscribedPodcasts: [Podcast] = []
    /// The last episode that was played.
    @State private var lastPlayedEpisode: PodcastEpisode? = nil
    
    /// Currently selected podcast.
    @State private var selectedPodcast: Podcast?
    /// Index of the selected episode within the active episode list.
    @State private var selectedEpisodeIndex: Int?
    
    // UI state flags controlling visibility and behavior.
    @State private var isCuePlaying = false
    @State private var isSearching = false
    @State private var isCueVisible = false
    @State private var isFavoritesVisible = false
    @State private var isPodcastLoading = false
    @State private var isAudioOutputSelectionVisible = false
    @State private var isSubscribeVisible = false
    @State private var isSettingsVisible = false
    
    // Add a new state variable to track initialization
    @State private var isInitialized = false
    
    /// Computes the list of episodes to display.
    /// If the cue is playing, returns the cue episodes; otherwise, returns episodes from the selected podcast.
    var activeEpisodes: [PodcastEpisode] {
        if isCuePlaying {
            return cue
        } else if let p = selectedPodcast {
            return p.episodes
        }
        return []
    }
    
    /// Builds a view that displays the title of the currently playing podcast or episode.
    var currentPlayingTitle: some View {
        if let currentEpisode = activeEpisodes.indices.contains(selectedEpisodeIndex ?? -1) ? activeEpisodes[selectedEpisodeIndex!] : nil {
            // Wrap the title in a horizontal stack with optional button behavior when cue is playing.
            return AnyView(
                HStack {
                    Spacer()
                    if isCuePlaying {
                        // Tapping toggles the cue visibility.
                        Button(action: {
                            isCueVisible.toggle()
                        }) {
                            Text("\(currentEpisode.podcastName ?? "Unknown Podcast")")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    } else {
                        // Display the selected podcast title.
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
        Group {
            if isInitialized {
                // Main content - only show when fully initialized
                VStack(spacing: 12) {
                    // Player controls view.
                    PlayerView(
                        audioPlayer: audioPlayer,
                        episodes: activeEpisodes,
                        currentEpisodeIndex: $selectedEpisodeIndex,
                        feedArtworkURL: isCuePlaying ? nil : selectedPodcast?.feedArtworkURL
                    )
                    .padding(.bottom, 12)  // Extra bottom padding for separation.
                    
                    // Title display section for current playing podcast/episode.
                    currentPlayingTitle
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    
                    // Episode list section with loading indicator overlay.
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
                            // Inform the user if no episodes are available.
                            Text("No episodes available")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        // Show a progress indicator while the podcast is loading.
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
                // Toolbar with various action buttons.
                .toolbar { toolbarContent }
            } else {
                // Loading screen
                VStack {
                    ProgressView("Loading PodRams...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                    Text("Preparing your podcasts")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(minWidth: 600, minHeight: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // These modifiers apply to both states
        .frame(minWidth: 600, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Popovers and other modifiers
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
        // Popover for displaying the cue (play queue).
        .popover(isPresented: $isCueVisible) {
            CueSheetView(
                cue: $cue,
                isCuePlaying: $isCuePlaying,
                selectedEpisodeIndex: $selectedEpisodeIndex,
                audioPlayer: audioPlayer
            )
            .frame(minWidth: 400, minHeight: 500)
        }
        // Popover for displaying favorites.
        .popover(isPresented: $isFavoritesVisible) {
            FavoritesView(
                favoritePodcasts: $favoritePodcasts,
                selectedPodcast: $selectedPodcast,
                selectedEpisodeIndex: $selectedEpisodeIndex,
                audioPlayer: audioPlayer,
                podcastFetcher: podcastFetcher
            )
            .onDisappear {
                // Persist favorites when the view disappears.
                PersistenceManager.saveFavorites(favoritePodcasts)
            }
            .frame(minWidth: 400, minHeight: 500)
        }
        // Background view to capture keyboard shortcuts.
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
        // Task to load persisted data on view startup.
        .task {
            // Load persisted data
            favoritePodcasts = await PersistenceManager.loadFavorites()
            cue = await PersistenceManager.loadCue()
            subscribedPodcasts = await PersistenceManager.loadSubscriptions()
            lastPlayedEpisode = await PersistenceManager.loadLastPlayback()
            
            if let lastEp = lastPlayedEpisode,
               let feedUrl = lastEp.feedUrl, !feedUrl.isEmpty {
                // Create a temporary podcast object from the last played episode
                let cachedPodcast = Podcast(title: lastEp.title, feedUrl: feedUrl, episodes: [lastEp])
                cachedPodcast.feedArtworkURL = lastEp.artworkURL
                
                // Set initial state
                selectedPodcast = cachedPodcast
                selectedEpisodeIndex = 0
                isPodcastLoading = true
                
                // Fetch the full list of episodes first
                let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: cachedPodcast)
                
                await MainActor.run {
                    // Update podcast with fetched data
                    cachedPodcast.episodes = episodes
                    if let feedArt = feedArt {
                        cachedPodcast.feedArtworkURL = feedArt
                    }
                    
                    // Update selected podcast and episode index
                    selectedPodcast = cachedPodcast
                    if let index = episodes.firstIndex(where: { $0.url == lastEp.url }) {
                        selectedEpisodeIndex = index
                    }
                    
                    // Now that everything is loaded, start playback
                    audioPlayer.setPlayingState(true)
                    audioPlayer.playAudio(url: lastEp.url)
                    
                    // Mark initialization as complete and loading as finished
                    isPodcastLoading = false
                    isInitialized = true
                }
            } else {
                // No last episode to resume, just mark as initialized
                isInitialized = true
            }
        }
        // Listen for notifications to add a test podcast.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddTestPodcast"))) { notification in
            if let testPodcast = notification.userInfo?["podcast"] as? Podcast {
                subscribedPodcasts.append(testPodcast)
                selectedPodcast = testPodcast
                selectedEpisodeIndex = 0
            }
        }
        // Listen for notifications to add a test episode to the cue.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddTestEpisode"))) { notification in
            if let testEpisode = notification.userInfo?["episode"] as? PodcastEpisode {
                cue.append(testEpisode)
                isCuePlaying = true
                selectedEpisodeIndex = cue.count - 1
            }
        }
    }
    
    /// Defines the toolbar items including buttons for audio output, subscription, settings, favorites, cue, and search.
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // Button to toggle audio output selection.
            Button(action: { isAudioOutputSelectionVisible.toggle() }) {
                Image(systemName: AudioOutputManager.shared.currentRouteIcon)
            }
            .popover(isPresented: $isAudioOutputSelectionVisible) {
                AudioOutputSelectionView()
            }
            
            // Button to open the subscribe popover.
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
            
            // Button to open the settings popover.
            Button(action: { isSettingsVisible = true }) {
                Image(systemName: "gear")
            }
            .popover(isPresented: $isSettingsVisible) {
                SettingsView()
            }
            
            // Button to show favorites; disabled if there are no favorites.
            Button(action: { isFavoritesVisible = true }) {
                Image(systemName: "star")
            }
            .disabled(favoritePodcasts.isEmpty)
            .help("Favorites (\(favoritePodcasts.count))")
            
            // Button to show the cue (play queue); disabled if cue is empty.
            Button(action: { if !cue.isEmpty { isCueVisible.toggle() } }) {
                Image(systemName: "list.bullet")
            }
            .disabled(cue.isEmpty)
            .help("Cue (\(cue.count))")
            
            // Button to toggle the search popover.
            Button(action: { isSearching.toggle() }) {
                Image(systemName: "magnifyingglass")
            }
            .help("Search for Podcasts")
        }
    }
    
    /// Toggles play/pause on the audio player.
    /// If the audio is playing, it pauses; otherwise, it plays the currently selected episode.
    private func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pauseAudio()
        } else if let index = selectedEpisodeIndex, index < activeEpisodes.count {
            audioPlayer.playAudio(url: activeEpisodes[index].url)
        }
    }
}

// Add this helper function to format time durations
extension Double {
    func formatAsPlaybackTime() -> String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

/// Represents a single row in the episode list.
struct EpisodeRow: View {
    /// The episode to display.
    let episode: PodcastEpisode
    /// Flag indicating if this episode is currently playing.
    let isPlaying: Bool
    /// Flag indicating if the episode is in the cue.
    let isInCue: Bool
    /// Current playback time used to update the progress bar.
    let currentTime: Double
    /// Total duration of the episode.
    let duration: Double
    /// Reference to the audio player to check play/pause state
    @ObservedObject var audioPlayer: AudioPlayer
    /// Optional closure to handle seeking to a new time.
    var onSeek: ((Double) -> Void)?
    /// Optional closure called when the episode is selected.
    var onSelect: (() -> Void)?
    /// Optional closure to toggle the cue state for the episode.
    var onToggleCue: (() -> Void)?
    /// Optional closure to trigger a download.
    var onDownload: (() -> Void)?
    /// Local state to track whether the mouse is hovering over the row.
    @State var isHovering = false
    
    // Add this to force an update when the view appears
    @State private var hasAppeared = false
    
    // Add this to ensure we're tracking both currentTime and isPlaying changes
    private var audioPlayerStatePublisher: AnyPublisher<(Double, Bool), Never> {
        Publishers.CombineLatest(
            audioPlayer.$currentTime.removeDuplicates(),
            audioPlayer.$isPlaying.removeDuplicates()
        )
        .eraseToAnyPublisher()
    }
    
    var formattedTime: String {
        if isPlaying {
            // For playing episodes, show current time and total duration
            // Current time counts up from 0 to duration
            return "\(currentTime.formatAsPlaybackTime()) of \(duration.formatAsPlaybackTime())"
        } else if duration > 0 {
            // For non-playing episodes with known duration, just show the total time
            return duration.formatAsPlaybackTime()
        } else {
            // For episodes with unknown duration
            return "--:--"
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Play/speaker icon section with forced display for playing episodes
            if isPlaying {
                // Always show speaker icon for the playing episode when not hovering
                if !isHovering {
                    // Force display of speaker icon for playing episodes
                    Image(systemName: audioPlayer.isPlaying ? "speaker.3.fill" : "speaker.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .id("speaker-\(episode.id)-\(audioPlayer.isPlaying)") // Force redraw when state changes
                } else {
                    // Show play/pause icon on hover based on current state
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                        .frame(width: 16)
                }
            } else if isHovering {
                // Show play icon when hovering over non-playing episodes
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                    .frame(width: 16)
            } else {
                // Empty space for non-playing, non-hovering episodes
                Spacer()
                    .frame(width: 16)
            }
            
            // Button that selects the episode
            Button(action: {
                onSelect?()
            }) {
                // Simplified layout without the progress bar
                HStack {
                    Text(episode.title)
                        .lineLimit(1)
                        .foregroundColor(isPlaying ? .white : .primary)
                    Spacer()
                    
                    // Single time display
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundColor(isPlaying ? .white.opacity(0.8) : .gray)
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
            .onHover { hovering in
                isHovering = hovering
            }
            
            // If the episode is in the cue, show an icon that can be tapped to toggle its cue state.
            if isInCue {
                Image(systemName: "music.note.list")
                    .foregroundColor(.blue)
                    .frame(width: 40)
                    .padding(.trailing, 8)
                    .onTapGesture {
                        onToggleCue?()
                    }
            }
            
            // Button to download the episode.
            DownloadButton(episode: episode)
                .frame(width: 40)
                .padding(.trailing, 8)
        }
        .id("row-\(episode.id)-\(isPlaying)-\(audioPlayer.isPlaying)") // Force redraw when state changes
        .onAppear {
            // Force a refresh when the view appears
            hasAppeared = true
        }
        // Update to use the combined publisher
        .onReceive(audioPlayerStatePublisher) { _, _ in
            // This empty closure forces the view to update when audio player state changes
        }
    }
}
