import SwiftUI
import Combine

/// Main content view for the podcast app.
/// Combines podcast fetching, audio playback, and various UI states.
struct ContentView: View {
    /// Fetches podcast data asynchronously.
    @StateObject var podcastFetcher = PodcastFetcher()
    /// Manages audio playback and related state.
    @EnvironmentObject var audioPlayer: AudioPlayer
    
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
    private var activeEpisodes: [PodcastEpisode] {
        if isCuePlaying {
            return cue
        } else if let podcast = selectedPodcast {
            return podcast.episodes
        }
        return []
    }
    
    // Add a binding for episodes to keep them in sync with the app state
    @Binding var appEpisodes: [PodcastEpisode]
    @Binding var appCurrentEpisodeIndex: Int?
    
    init(appEpisodes: Binding<[PodcastEpisode]> = .constant([]), appCurrentEpisodeIndex: Binding<Int?> = .constant(nil)) {
        _appEpisodes = appEpisodes
        _appCurrentEpisodeIndex = appCurrentEpisodeIndex
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
                                .foregroundColor(.white)
                                .background(Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(Color.clear)
                    } else {
                        // Display the selected podcast title.
                        Text(selectedPodcast?.title ?? "Unknown Podcast")
                            .font(.headline)
                            .background(Color.clear)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.clear)
            )
        }
        return AnyView(EmptyView())
    }
    
    var body: some View {
        Group {
            if isInitialized {
                // Main content - only show when fully initialized
                VStack(spacing: 8) {
                    // Player controls view.
                    PlayerView(
                        audioPlayer: audioPlayer,
                        episodes: activeEpisodes,
                        currentEpisodeIndex: $selectedEpisodeIndex,
                        feedArtworkURL: isCuePlaying ? nil : selectedPodcast?.feedArtworkURL
                    )
                    .padding(.bottom, 8)  // Reduced padding
                    
                    // Title display section for current playing podcast/episode.
                    currentPlayingTitle
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8) // Reduced padding
                    
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
                                cueList: $cue,
                                isCuePlaying: $isCuePlaying
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1) // Give the episode list higher layout priority
                }
                .padding()
                .frame(minWidth: 600, minHeight: 600)
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
                .frame(minWidth: 600, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // These modifiers apply to both states
        .frame(minWidth: 600, minHeight: 600)
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
                subscribedPodcasts: $subscribedPodcasts,
                onPodcastSelect: handlePodcastSelect
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
                audioPlayer: audioPlayer,
                selectedPodcast: $selectedPodcast
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
            
            // Prefetch episodes for subscribed podcasts in the background
            Task(priority: .background) {
                await prefetchSubscribedPodcasts()
            }
        }
        // Listen for notifications to add a test podcast.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddTestPodcast"))) { notification in
            if let testPodcast = notification.userInfo?["podcast"] as? Podcast {
                // Create a new array to avoid direct state modification
                var updatedSubscriptions = subscribedPodcasts
                updatedSubscriptions.append(testPodcast)
                subscribedPodcasts = updatedSubscriptions
                
                selectedPodcast = testPodcast
                selectedEpisodeIndex = 0
            }
        }
        // Listen for notifications to add a test episode to the cue.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddTestEpisode"))) { notification in
            if let testEpisode = notification.userInfo?["episode"] as? PodcastEpisode {
                // Create a new array to avoid direct state modification
                var updatedCue = cue
                updatedCue.append(testEpisode)
                cue = updatedCue
                
                // Save the cue and post notification
                if let feedUrl = testEpisode.feedUrl {
                    PersistenceManager.saveCue(cue, feedUrl: feedUrl)
                    NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                }
                
                isCuePlaying = true
                selectedEpisodeIndex = cue.count - 1
            }
        }
        // Keep app state in sync with ContentView state
        .onChange(of: activeEpisodes) { newEpisodes in
            appEpisodes = newEpisodes
        }
        .onChange(of: selectedEpisodeIndex) { newIndex in
            appCurrentEpisodeIndex = newIndex
        }
    }
    
    /// Defines the toolbar items including buttons for audio output, subscription, settings, favorites, cue, and search.
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // Button to toggle audio output selection.
            Button(action: { isAudioOutputSelectionVisible.toggle() }) {
                Image(systemName: AudioOutputManager.shared.currentRouteIcon)
            }
            .accessibilityIdentifier("AudioOutputButton")
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
                    selectedEpisodeIndex: $selectedEpisodeIndex,
                    podcastFetcher: podcastFetcher,
                    audioPlayer: audioPlayer,
                    onPodcastSelect: handlePodcastSelect
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
    
    /// Loads the podcast episodes, updates the UI state, and starts playback if requested.
    private func handlePodcastSelect(_ podcast: Podcast, autoPlay: Bool = false) {
        // Reset cue playing state when selecting a podcast
        isCuePlaying = false
        
        // If we're already viewing this podcast, just return
        if let selected = selectedPodcast, selected.id == podcast.id {
            return
        }
        
        // Set loading state and update selected podcast
        isPodcastLoading = true
        selectedPodcast = podcast
        selectedEpisodeIndex = nil
        
        // Fetch episodes for the selected podcast
        Task {
            let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
            
            await MainActor.run {
                // Update podcast with fetched data
                podcast.episodes = episodes
                if let feedArt = feedArt {
                    podcast.feedArtworkURL = feedArt
                }
                
                // Update selected podcast and episode index
                selectedPodcast = podcast
                
                // If autoPlay is true, start playback of the first episode
                if autoPlay && !episodes.isEmpty {
                    // First set the episode index
                    selectedEpisodeIndex = 0
                    
                    // Then start playback with a small delay to ensure UI is updated
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // Make sure we're still on the same podcast/episode
                        if selectedPodcast?.id == podcast.id && selectedEpisodeIndex == 0 {
                            audioPlayer.playAudio(url: episodes[0].url)
                        }
                    }
                }
                
                // Mark loading as finished
                isPodcastLoading = false
            }
        }
    }
    
    /// Prefetches episodes for all subscribed podcasts in the background
    private func prefetchSubscribedPodcasts() async {
        print("Starting background prefetch of \(subscribedPodcasts.count) subscribed podcasts")
        
        for podcast in subscribedPodcasts {
            // Skip podcasts that already have episodes loaded
            if !podcast.episodes.isEmpty {
                continue
            }
            
            // Fetch episodes for this podcast
            let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
            
            // Update the podcast with the fetched episodes
            await MainActor.run {
                podcast.episodes = episodes
                if let feedArt = feedArt {
                    podcast.feedArtworkURL = feedArt
                }
            }
            
            // Preload the first episode's audio to reduce playback startup time
            if let firstEpisode = episodes.first {
                audioPlayer.preloadAudio(url: firstEpisode.url)
            }
            
            print("Prefetched \(episodes.count) episodes for \(podcast.title)")
            
            // Add a small delay between fetches to avoid overwhelming the network
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("Completed background prefetch of subscribed podcasts")
    }
}

// Add this helper function to format time durations
extension Double {
    func formatAsPlaybackTime() -> String {
        // Handle invalid inputs
        guard self.isFinite && self >= 0 else {
            return "00:00"
        }
        
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
    
    @State private var isHovering = false
    @State private var showMenu = false
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var formattedTime: String {
        // Ensure we have valid time values
        guard currentTime.isFinite && duration.isFinite && 
              currentTime >= 0 && duration >= 0 else {
            return "00:00"
        }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        if isPlaying {
            // For playing episodes, show current time / total time
            let safeCurrentTime = min(currentTime, duration) // Ensure current time doesn't exceed duration
            let currentTimeString = formatter.string(from: safeCurrentTime) ?? "00:00"
            let durationString = formatter.string(from: duration) ?? "00:00"
            return "\(currentTimeString) / \(durationString)"
        } else {
            // For non-playing episodes, just show the duration
            return formatter.string(from: duration) ?? "00:00"
        }
    }
    
    /// Determines if the menu should be shown based on available actions
    private var shouldShowMenu: Bool {
        // Show menu if either add to cue or download options are available
        return onToggleCue != nil || onDownload != nil
    }
    
    /// Gets the current download state for this episode
    private var downloadState: DownloadManager.DownloadState {
        return downloadManager.downloadStates[episode.url.absoluteString] ?? DownloadManager.DownloadState.none
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
                        .id("speaker-\(episode.id)-\(audioPlayer.isPlaying)") // Force redraw with unique ID
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
            
            Spacer(minLength: 10) // Keep spacing between buttons
            
            // Single action button area - either menu or progress indicator
            if case .downloading(let progress) = downloadState {
                // Show download progress indicator when downloading
                DeterminateLoadingIndicator(progress: progress)
                    .frame(width: 40, height: 30)
                    .padding(.trailing, 8)
            } else if shouldShowMenu {
                // Show ellipsis menu when not downloading
                Menu {
                    // Add to cue option
                    if let toggleCue = onToggleCue {
                        Button(action: toggleCue) {
                            Label(
                                isInCue ? "Remove from cue" : "Add to cue",
                                systemImage: "music.note.list"
                            )
                        }
                    }
                    
                    // Download option - show different options based on download state
                    if let download = onDownload {
                        switch downloadState {
                        case .none:
                            Button(action: download) {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        case .downloaded:
                            Button(action: {
                                downloadManager.removeDownload(for: episode)
                            }) {
                                Label("Delete download", systemImage: "trash")
                            }
                        case .failed:
                            Button(action: download) {
                                Label("Retry download", systemImage: "arrow.clockwise")
                            }
                        case .downloading:
                            // No action for downloading state
                            EmptyView()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                        .frame(width: 40, height: 30)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden) // Hide the menu indicator arrow
                .frame(width: 40)
                .padding(.trailing, 8)
            }
        }
        .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            // Let the system handle cursor behavior naturally
        }
        // Use a stable ID that only changes when necessary
        .id("row-\(episode.id)-\(isPlaying)-\(audioPlayer.isPlaying)")
    }
}
