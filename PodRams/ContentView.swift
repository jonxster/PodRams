import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

/// Main content view for the podcast app.
/// Combines podcast fetching, audio playback, and various UI states.
struct ContentView: View {
    /// Fetches podcast data asynchronously.
    @StateObject var podcastFetcher = PodcastFetcher()
    /// Manages audio playback and related state.
    @EnvironmentObject var audioPlayer: AudioPlayer
    /// Tracks the current system color scheme so toolbar styling matches appearance.
    @Environment(\.colorScheme) private var colorScheme
    /// Memory optimization manager to reduce app memory footprint
    @StateObject private var memoryOptimizer = MemoryOptimizationManager.shared
    
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

    /// Namespace used for Liquid Glass morphing identifiers.
    @Namespace private var glassNamespace
    
    // UI state flags controlling visibility and behavior.
    @State private var isCuePlaying = false
    @State private var isSearching = false
    @State private var isCueVisible = false
    @State private var isFavoritesVisible = false
    @State private var isPodcastLoading = false
    @State private var isAudioOutputSelectionVisible = false
    @State private var isSubscribeVisible = false
    @State private var isSettingsVisible = false
    @State private var isShowNotesVisible = false
    @State private var isShowNotesLoading = false
    @State private var showNotesContent: AttributedString = AttributedString("Select an episode to view show notes.")
    @State private var showNotesEpisodeID: String?
    @State private var showNotesTitle: String = "Show Notes"
    
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
    
    private var currentShowNotesEpisode: PodcastEpisode? {
        guard let index = selectedEpisodeIndex else { return nil }
        let episodes = activeEpisodes
        guard episodes.indices.contains(index) else { return nil }
        return episodes[index]
    }
    
    private var showNotesAvailable: Bool {
        !isShowNotesLoading && currentShowNotesEpisode != nil
    }
    
    // Add a binding for episodes to keep them in sync with the app state
    @Binding var appEpisodes: [PodcastEpisode]
    @Binding var appCurrentEpisodeIndex: Int?
    @Binding var appSelectedPodcast: Podcast?
    
    struct InitialState {
        var favoritePodcasts: [Podcast] = []
        var cue: [PodcastEpisode] = []
        var subscribedPodcasts: [Podcast] = []
        var lastPlayedEpisode: PodcastEpisode? = nil
        var selectedPodcast: Podcast? = nil
        var selectedEpisodeIndex: Int? = nil
        var isCuePlaying: Bool = false
        var isInitialized: Bool = false
    }

    init(appEpisodes: Binding<[PodcastEpisode]> = .constant([]),
         appCurrentEpisodeIndex: Binding<Int?> = .constant(nil),
         appSelectedPodcast: Binding<Podcast?> = .constant(nil),
         initialState: InitialState? = nil) {
        _appEpisodes = appEpisodes
        _appCurrentEpisodeIndex = appCurrentEpisodeIndex
        _appSelectedPodcast = appSelectedPodcast

        if let initialState {
            _favoritePodcasts = State(initialValue: initialState.favoritePodcasts)
            _cue = State(initialValue: initialState.cue)
            _subscribedPodcasts = State(initialValue: initialState.subscribedPodcasts)
            _lastPlayedEpisode = State(initialValue: initialState.lastPlayedEpisode)
            _selectedPodcast = State(initialValue: initialState.selectedPodcast)
            _selectedEpisodeIndex = State(initialValue: initialState.selectedEpisodeIndex)
            _isCuePlaying = State(initialValue: initialState.isCuePlaying)
            _isInitialized = State(initialValue: initialState.isInitialized)
        }
    }
    
    /// Builds a view that displays the title of the currently playing podcast or episode.
    @ViewBuilder
    var currentPlayingTitle: some View {
        if let index = selectedEpisodeIndex,
           activeEpisodes.indices.contains(index) {
            let episode = activeEpisodes[index]
            let cueTitle = episode.podcastName ?? "Unknown Podcast"
            let podcastTitle = selectedPodcast?.title ?? cueTitle

            if isCuePlaying {
                Button {
                    isCueVisible.toggle()
                } label: {
                    Text(cueTitle)
                        .font(.headline)
                        .foregroundColor(AppTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .glassEffectID("now-playing-title", in: glassNamespace)
                }
                .buttonStyle(.glass(.regular.interactive()))
            } else {
                Text(podcastTitle)
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .glassEffectID("now-playing-title", in: glassNamespace)
            }
        }
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
                    .padding(.bottom, 24)
                    
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
                                .foregroundColor(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        // Show a progress indicator while the podcast is loading.
                        if isPodcastLoading {
                            ProgressView("Loading podcast...")
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(AppTheme.accent)
                                .foregroundColor(AppTheme.secondaryText)
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
                .toolbarBackground(AppTheme.toolbarBackground, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(colorScheme, for: .windowToolbar)
                .glassBackgroundEffect(.window)
            } else {
                // Loading screen
                VStack {
                    ProgressView("Loading PodRams...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(AppTheme.accent)
                        .padding()
                    Text("Preparing your podcasts")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
                .frame(minWidth: 600, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // These modifiers apply to both states
        .frame(minWidth: 600, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
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
            .glassBackgroundEffect(.window)
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
            .glassBackgroundEffect(.sidebar)
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
            .frame(minWidth: 400, minHeight: 400)
            .glassBackgroundEffect(.window)
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
            print("🔄 ContentView: Starting app initialization...")
            
            // Initialize memory optimization system
            PersistenceManager.setupMemoryOptimization()
            
            // Load persisted data first
            favoritePodcasts = await PersistenceManager.loadFavorites()
            cue = await PersistenceManager.loadCue()
            subscribedPodcasts = await PersistenceManager.loadSubscriptions()
            lastPlayedEpisode = await PersistenceManager.loadLastPlayback()
            
            print("📱 ContentView: Loaded persisted data - Favorites: \(favoritePodcasts.count), Cue: \(cue.count), Subscriptions: \(subscribedPodcasts.count), Last episode: \(lastPlayedEpisode?.title ?? "none")")
            
            // Optimize memory usage after loading data
            Task.detached(priority: .background) {
                await MainActor.run {
                    // Optimize podcast episode collections to reduce memory usage
                    for podcast in favoritePodcasts {
                        podcast.optimizeMemoryUsage()
                    }
                    for podcast in subscribedPodcasts {
                        podcast.optimizeMemoryUsage()
                    }
                }
            }
            
            // Handle resume of last played episode if available
            if let lastEp = lastPlayedEpisode,
               let feedUrl = lastEp.feedUrl, !feedUrl.isEmpty {
                
                print("🎵 ContentView: Attempting to restore last played episode: \(lastEp.title)")
                
                // Find the podcast in subscriptions first
                if let subscribedPodcast = subscribedPodcasts.first(where: { $0.feedUrl == feedUrl }) {
                    print("✅ ContentView: Found podcast in subscriptions: \(subscribedPodcast.title)")
                    
                    // Use the subscribed podcast and fetch its episodes
                    selectedPodcast = subscribedPodcast
                    isPodcastLoading = true
                    
                    let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: subscribedPodcast)
                    
                    await MainActor.run {
                        // Update podcast with fetched data
                        subscribedPodcast.episodes = episodes
                        if let feedArt = feedArt {
                            subscribedPodcast.feedArtworkURL = feedArt
                        }
                        
                        // Find and set the correct episode index
                        if let index = episodes.firstIndex(where: { $0.url == lastEp.url }) {
                            selectedEpisodeIndex = index
                            print("🎯 ContentView: Restored episode index: \(index)")
                            
                            // Restore playback
                            audioPlayer.playEpisode(lastEp)
                            print("▶️ ContentView: Started playback of restored episode")
                        } else {
                            // Episode not found in current episodes, play first episode if available
                            if !episodes.isEmpty {
                                selectedEpisodeIndex = 0
                                print("⚠️ ContentView: Last episode not found, using first episode")
                            }
                        }
                        
                        isPodcastLoading = false
                    }
                } else {
                    // Podcast not in subscriptions, create a temporary one
                    print("⚠️ ContentView: Podcast not found in subscriptions, creating temporary podcast")
                    let tmpPodcast = Podcast(title: lastEp.podcastName ?? "Unknown Podcast", feedUrl: feedUrl)
                    tmpPodcast.feedArtworkURL = lastEp.artworkURL
                    
                    selectedPodcast = tmpPodcast
                    isPodcastLoading = true
                    
                    let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: tmpPodcast)
                    
                    await MainActor.run {
                        tmpPodcast.episodes = episodes
                        if let feedArt = feedArt {
                            tmpPodcast.feedArtworkURL = feedArt
                        }
                        
                        if let index = episodes.firstIndex(where: { $0.url == lastEp.url }) {
                            selectedEpisodeIndex = index
                            audioPlayer.playEpisode(lastEp)
                        } else if !episodes.isEmpty {
                            selectedEpisodeIndex = 0
                        }
                        
                        isPodcastLoading = false
                    }
                }
            } else {
                print("ℹ️ ContentView: No last played episode to restore")
            }

            // Mark initialization complete AFTER restoration is done
            print("✅ ContentView: App initialization complete")
            isInitialized = true
            refreshShowNotes()
            
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
        .onChange(of: activeEpisodes) { _, newEpisodes in
            appEpisodes = newEpisodes
            refreshShowNotes()
        }
        .onChange(of: selectedEpisodeIndex) { _, newIndex in
            appCurrentEpisodeIndex = newIndex
            refreshShowNotes()
        }
        .onChange(of: selectedPodcast) { _, newPodcast in
            appSelectedPodcast = newPodcast
            refreshShowNotes()
        }
        .onChange(of: cue) { _, _ in
            refreshShowNotes()
        }
        .onChange(of: isCuePlaying) { _, _ in
            refreshShowNotes()
        }
    }
    
    /// Defines the toolbar items including buttons for audio output, subscription, settings, favorites, cue, and search.
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // Button to toggle audio output selection.
            Button {
                isAudioOutputSelectionVisible.toggle()
            } label: {
                glassToolbarIcon(AudioOutputManager.shared.currentRouteIcon)
            }
            .accessibilityIdentifier("AudioOutputButton")
            .popover(isPresented: $isAudioOutputSelectionVisible) {
                AudioOutputSelectionView()
                    .glassBackgroundEffect(.sidebar)
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            // Button to open the subscribe popover.
            Button {
                isSubscribeVisible = true
            } label: {
                glassToolbarIcon("rectangle.and.paperclip", isEnabled: !subscribedPodcasts.isEmpty)
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
                .glassBackgroundEffect(.inspector)
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            // Button to open the settings popover.
            Button {
                isSettingsVisible = true
            } label: {
                glassToolbarIcon("gearshape")
            }
            .popover(isPresented: $isSettingsVisible) {
                SettingsView()
                    .glassBackgroundEffect(.window)
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            // Button to show favorites; disabled if there are no favorites.
            Button {
                isFavoritesVisible = true
            } label: {
                glassToolbarIcon("star.fill", isEnabled: !favoritePodcasts.isEmpty)
            }
            .disabled(favoritePodcasts.isEmpty)
            .help("Favorites (\(favoritePodcasts.count))")
            .buttonStyle(.plain)
            .focusable(false)
            
            // Button to show the cue (play queue); disabled if cue is empty.
            Button {
                if !cue.isEmpty { isCueVisible.toggle() }
            } label: {
                glassToolbarIcon("list.bullet", isEnabled: !cue.isEmpty)
            }
            .disabled(cue.isEmpty)
            .help("Cue (\(cue.count))")
            .buttonStyle(.plain)
            .focusable(false)

            // Button to show show notes for the current episode.
            Button {
                if showNotesAvailable {
                    if isShowNotesVisible {
                        isShowNotesVisible = false
                    } else {
                        refreshShowNotes()
                        isShowNotesVisible = true
                    }
                }
            } label: {
                let symbol = resolveSymbolName(primary: "text.bubble", fallbacks: ["text.alignleft", "text.justify", "doc.text"])
                glassToolbarIcon(symbol, isEnabled: showNotesAvailable)
            }
            .disabled(!showNotesAvailable)
            .help("Show Notes")
            .popover(isPresented: $isShowNotesVisible) {
                ShowNotesView(
                    episodeTitle: showNotesTitle,
                    isLoading: isShowNotesLoading,
                    notes: showNotesContent
                )
                .glassBackgroundEffect(.window)
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            // Button to toggle the search popover.
            Button {
                isSearching.toggle()
            } label: {
                glassToolbarIcon("magnifyingglass")
            }
            .help("Search for Podcasts")
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    /// Toggles play/pause on the audio player.
    /// If the audio is playing, it pauses; otherwise, it plays the currently selected episode.
    private func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pauseAudio()
        } else if let index = selectedEpisodeIndex, index < activeEpisodes.count {
            let episode = activeEpisodes[index]
            audioPlayer.playEpisode(episode)
        }
    }
    
    private func refreshShowNotes() {
        prepareShowNotes(for: currentShowNotesEpisode)
    }

    private func prepareShowNotes(for episode: PodcastEpisode?) {
        guard let episode else {
            showNotesEpisodeID = nil
            showNotesTitle = ""
            showNotesContent = AttributedString("Select an episode to view show notes.")
            isShowNotesLoading = false
            if isShowNotesVisible {
                isShowNotesVisible = false
            }
            return
        }

        showNotesTitle = episode.title
        let loadID = episode.id
        showNotesEpisodeID = loadID

        guard let rawNotes = episode.showNotes, !rawNotes.isEmpty else {
            isShowNotesLoading = false
            showNotesContent = AttributedString("No show notes available.")
            return
        }

        isShowNotesLoading = true
        showNotesContent = AttributedString("Loading show notes...")

        let targetID = loadID
        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = rawNotes.htmlRenderedAttributedString()
            DispatchQueue.main.async {
                if showNotesEpisodeID == targetID {
                    if rendered.characters.isEmpty {
                        showNotesContent = AttributedString("No show notes available.")
                    } else {
                        showNotesContent = rendered
                    }
                    isShowNotesLoading = false
                }
            }
        }
    }

    /// Loads the podcast episodes, updates the UI state, and starts playback if requested.
    private func handlePodcastSelect(_ podcast: Podcast, autoPlay: Bool = false) {
        // Reset cue playing state when selecting a podcast
        isCuePlaying = false

        let needsReload = selectedPodcast?.id != podcast.id || (selectedPodcast?.episodes.isEmpty ?? true)
        if !needsReload { return }

        selectedPodcast = podcast
        isPodcastLoading = true
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
                            if let firstEpisode = episodes.first {
                                audioPlayer.playEpisode(firstEpisode)
                            }
                        }
                    }
                }
                
                // Mark loading as finished
                isPodcastLoading = false
                refreshShowNotes()
            }
        }
    }

    private func glassToolbarIcon(_ systemName: String, isEnabled: Bool = true) -> some View {
        ToolbarIcon(systemName: resolveSymbolName(primary: systemName), isEnabled: isEnabled)
    }

    private struct ToolbarIcon: View {
        let systemName: String
        let isEnabled: Bool
        @State private var isHovering = false
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            RoundedRectangle(cornerRadius: 50, style: .circular)
                .fill(isHovering ? hoverFill : baseFill)
                .overlay(
                    Image(systemName: systemName)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .circular)
                        .stroke(strokeColor, lineWidth: 0.0)
                )
                .frame(width: 35, height: 35)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .onHover { hovering in
                    isHovering = hovering
                }
        }

        private var baseFill: Color {
            AppTheme.color(.surface, in: mode)
        }

        private var hoverFill: Color {
            AppTheme.color(.hoverSurface, in: mode)
        }

        private var strokeColor: Color {
            AppTheme.color(.secondaryText, in: mode)
                .opacity(isHovering ? 0.35 : (isEnabled ? (colorScheme == .dark ? 0.18 : 0.12) : 0.08))
        }

        private var iconColor: Color {
            let active = AppTheme.color(.primaryText, in: mode)
            let inactive = AppTheme.color(.secondaryText, in: mode)
            return isEnabled ? active : inactive
        }

        private var mode: AppTheme.Mode {
            colorScheme == .dark ? .dark : .light
        }
    }

    private func resolveSymbolName(primary: String, fallbacks: [String] = []) -> String {
        #if os(macOS)
        let safetyNet = "doc.text"
        let candidates = [primary] + fallbacks + [safetyNet]
        for symbol in candidates {
            if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
                return symbol
            }
        }
        return safetyNet
        #else
        return primary
        #endif
    }

    /// Prefetches episodes for all subscribed podcasts in the background
    private func prefetchSubscribedPodcasts() async {
        print("Starting optimized background prefetch of \(subscribedPodcasts.count) subscribed podcasts")

        // Limit concurrent prefetches for better performance
        let maxConcurrentPrefetches = 3
        var currentPrefetches = 0
        
        for podcast in subscribedPodcasts {
            // Skip podcasts that already have episodes loaded
            if !podcast.episodes.isEmpty {
                continue
            }
            
            // Wait if we have too many concurrent prefetches
            while currentPrefetches >= maxConcurrentPrefetches {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            currentPrefetches += 1
            
            Task {
                defer { currentPrefetches -= 1 }
                
                // Fetch episodes for this podcast
                let (episodes, feedArt) = await podcastFetcher.fetchEpisodesDirect(for: podcast)
                
                // Update the podcast with the fetched episodes
                await MainActor.run {
                    podcast.episodes = episodes
                    if let feedArt = feedArt {
                        podcast.feedArtworkURL = feedArt
                    }
                }
                
                // Preload only the first episode's audio to reduce startup time
                if let firstEpisode = episodes.first {
                    audioPlayer.preloadAudio(url: firstEpisode.url)
                }
                
                print("Prefetched \(episodes.count) episodes for \(podcast.title)")
            }
            
            // Add a smaller delay between starting fetches
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
        }
        
        print("Completed optimized background prefetch of subscribed podcasts")
    }
}

#if DEBUG
#Preview("ContentView Preview") {
    ContentViewPreviewContainer()
        .frame(minWidth: 900, minHeight: 600)
}
#endif

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
    
    // ADD environment variable for color scheme
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isHovering = false
    @State private var showMenu = false
    @ObservedObject private var downloadManager = DownloadManager.shared
    // ADD PlayedEpisodesManager observer
    @ObservedObject private var playedManager = PlayedEpisodesManager.shared
    
    var formattedTime: String {
        if isPlaying {
            // For playing episodes, get values directly from audioPlayer for real-time updates
            let currentPlayerTime = audioPlayer.currentTime
            let currentPlayerDuration = audioPlayer.duration
            
            // Ensure we have valid time values
            guard currentPlayerTime.isFinite && currentPlayerDuration.isFinite && 
                  currentPlayerTime >= 0 && currentPlayerDuration >= 0 && currentPlayerDuration > 0 else {
                return "00:00"
            }
            
            // For playing episodes, show remaining time as countdown
            let safeCurrentTime = min(currentPlayerTime, currentPlayerDuration) // Ensure current time doesn't exceed duration
            let remainingTime = max(currentPlayerDuration - safeCurrentTime, 0)
            
            // Use a simpler time formatting approach
            let remainingSeconds = Int(remainingTime)
            let hours = remainingSeconds / 3600
            let minutes = (remainingSeconds % 3600) / 60
            let seconds = remainingSeconds % 60
            
            if hours > 0 {
                return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d remaining", minutes, seconds)
            }
        } else {
            // For non-playing episodes, use the episode duration
            let episodeDuration = duration > 0 ? duration : (episode.duration ?? 0)
            
            guard episodeDuration.isFinite && episodeDuration >= 0 else {
                return "00:00"
            }
            
            let durationSeconds = Int(episodeDuration)
            let hours = durationSeconds / 3600
            let minutes = (durationSeconds % 3600) / 60
            let seconds = durationSeconds % 60
            
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d", minutes, seconds)
            }
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
    
    // ADD @ViewBuilder computed property for the indicator
    @ViewBuilder
    private var playedIndicatorView: some View {
        // Determine if the indicator should be visible (dot or non-zero spacer)
        let isIndicatorVisible = !playedManager.hasBeenPlayed(episode) || spacerWidthForPlayedEpisode() > 0
        
        // Add leading padding only if the indicator will be visible
        // Apply padding here instead of on the Circle/Spacer directly
        Group {
           if !playedManager.hasBeenPlayed(episode) {
               Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
                    // .padding(.trailing, 6) // REMOVE padding from here
            } else {
                // Spacer to maintain layout consistency when dot is hidden
                Spacer()
                    .frame(width: spacerWidthForPlayedEpisode()) // Use helper function
            }
        }
        .padding(.leading, isIndicatorVisible ? 6 : 0) // Add conditional leading padding
    }
    
    // Helper function to calculate spacer width
    private func spacerWidthForPlayedEpisode() -> CGFloat {
        let isDownloadingState: Bool
        if case .downloading = downloadState {
            isDownloadingState = true
        } else {
            isDownloadingState = false
        }
        let showNextElement = shouldShowMenu || isDownloadingState
        return showNextElement ? (8 + 6) : 0 // Match dot width + padding, or 0
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Play/speaker icon section with forced display for playing episodes
            if isPlaying {
                // Always show speaker icon for the playing episode when not hovering
                if !isHovering {
                    // Force display of speaker icon for playing episodes
                    Image(systemName: audioPlayer.isPlaying ? "speaker.3.fill" : "speaker.fill")
                        .foregroundColor(AppTheme.primaryText)
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .id("speaker-\(episode.id)-\(audioPlayer.isPlaying)") // Force redraw with unique ID
                } else {
                    // Show play/pause icon on hover based on current state
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(AppTheme.primaryText)
                        .font(.system(size: 12))
                        .frame(width: 16)
                }
            } else if isHovering {
                // Show play icon when hovering over non-playing episodes
                Image(systemName: "play.fill")
                    .foregroundColor(AppTheme.accent)
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
                let titleColor = AppTheme.primaryText
                let infoColor = AppTheme.primaryText.opacity(0.85)
                // Simplified layout without the progress bar
                HStack {
                    Text(episode.title)
                        .lineLimit(1)
                        .foregroundColor(titleColor)
                        .font(isPlaying ? .body.bold() : .body)
                    Spacer()
                    
                    // Single time display
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundColor(isPlaying ? infoColor : infoColor.opacity(0.85))
                        .id(isPlaying ? "time-\(episode.id)-\(Int(audioPlayer.currentTime))" : "time-\(episode.id)") // Force redraw for playing episodes
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            Spacer(minLength: 10) // Keep spacing between buttons
            
            // Single action button area - either menu or progress indicator
            if case .downloading(let progress) = downloadState {
                // Show hoverable download progress indicator when downloading
                HoverableDownloadIndicator(
                    episode: episode,
                    progress: progress,
                    isPaused: false
                )
                .frame(width: 40, height: 30)
                // Remove trailing padding here if indicator is last element
                // .padding(.trailing, 8)
            } else if case let .paused(progress, _) = downloadState {
                // Show hoverable download progress indicator when paused
                HoverableDownloadIndicator(
                    episode: episode,
                    progress: progress,
                    isPaused: true
                )
                .frame(width: 40, height: 30)
                // Remove trailing padding here if indicator is last element
                // .padding(.trailing, 8)
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
                        case .paused:
                            Button(action: {
                                downloadManager.resumeDownload(for: episode)
                            }) {
                                Label("Resume download", systemImage: "play.circle")
                            }
                        case .failed:
                            Button(action: download) {
                                Label("Retry download", systemImage: "arrow.clockwise")
                            }
                        case .downloading:
                            Button(action: {
                                downloadManager.pauseDownload(for: episode)
                            }) {
                                Label("Pause download", systemImage: "pause.circle")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(isPlaying ? AppTheme.primaryText : AppTheme.secondaryText)
                        .font(.system(size: 16))
                        .frame(width: 40, height: 30)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden) // Hide the menu indicator arrow
                .frame(width: 40)
                // Remove trailing padding here if indicator is last element
                // .padding(.trailing, 8)
            }

            // Use the computed property for the played indicator (NOW AT THE END)
            playedIndicatorView
                .padding(.trailing, 8) // Add overall trailing padding here
            
        }
        .padding(.vertical, isPlaying ? 4 : 0)
        .background(isHovering ? AppTheme.hoverSurface : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            // Let the system handle cursor behavior naturally
        }
        // Use a stable ID that only changes when necessary
        .id("row-\(episode.id)-\(isPlaying)-\(audioPlayer.isPlaying)")
    }
}
