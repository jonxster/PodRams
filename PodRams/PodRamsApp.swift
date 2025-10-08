#if !SWIFT_PACKAGE
import SwiftUI
import OSLog

private let appLifecycleLogger = AppLogger.app

@main
@MainActor
struct PodRamsApp: App {
    // Create a shared AudioPlayer instance at the app level with lazy initialization
    @StateObject private var audioPlayer = {
        // Initialize the audio player with error handling
        let player = AudioPlayer()
        appLifecycleLogger.info("AudioPlayer initialized successfully")
        return player
    }()
    
    // State for managing episodes and current episode index
    @State private var episodes: [PodcastEpisode] = []
    @State private var currentEpisodeIndex: Int?
    @State private var selectedPodcast: Podcast?
    
    // Add notification center observer for app lifecycle
    @State private var lifecycleObserver: Any?
    
    init() {
        // Set up any app-wide configurations
        appLifecycleLogger.info("PodRamsApp initializing...")
        
        #if DEBUG
        // We'll let the user run tests manually from the Debug menu instead
        // AppTests.runAllTests()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                appEpisodes: $episodes,
                appCurrentEpisodeIndex: $currentEpisodeIndex,
                appSelectedPodcast: $selectedPodcast
            )
            .environmentObject(audioPlayer) // Provide the audio player as an environment object
            .onAppear {
                // Log for debugging launch issues
                appLifecycleLogger.info("App launched at \(Date(), privacy: .public)")
                setupLifecycleObserver()
            }
            .onDisappear {
                cleanupLifecycleObserver()
            }
            .onChange(of: currentEpisodeIndex) { _, _ in
                Task { @MainActor in
                    saveCurrentState()
                }
            }
            .onChange(of: episodes) { _, _ in
                Task { @MainActor in
                    saveCurrentState()
                }
            }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Add the Play menu before the Debug menu
            PlayCommands(
                audioPlayer: audioPlayer,
                currentEpisodeIndex: $currentEpisodeIndex,
                episodes: episodes
            )
            
            // Add the Help menu
            HelpCommands()
            
            // Add the Debug menu
            DebugCommands()
        }
    }
    
    /// Sets up observer for app lifecycle events to save state when needed
    private func setupLifecycleObserver() {
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            appLifecycleLogger.info("🔄 App will terminate - saving current state")
            Task { @MainActor in
                saveCurrentState()
            }
        }
        
        // Also save state when app becomes inactive (like when switching apps)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            appLifecycleLogger.info("🔄 App resigned active - saving current state")
            Task { @MainActor in
                saveCurrentState()
            }
        }
    }
    
    /// Removes lifecycle observers
    private func cleanupLifecycleObserver() {
        if let observer = lifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
            lifecycleObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
    }
    
    /// Saves the current playback state for persistence
    private func saveCurrentState() {
        guard let index = currentEpisodeIndex, 
              index < episodes.count else {
            appLifecycleLogger.warning("⚠️ PodRamsApp: No valid current episode to save")
            return
        }
        
        let currentEpisode = episodes[index]
        
        // Try to determine the feed URL from the episode or selected podcast
        let feedUrl = currentEpisode.feedUrl ?? selectedPodcast?.feedUrl
        
        let episodeTitle = currentEpisode.title
        let feedIdentifier = feedUrl ?? "unknown"
        appLifecycleLogger.info("💾 PodRamsApp: Saving current state - Episode: \(episodeTitle, privacy: .private), Feed: \(feedIdentifier, privacy: .private)")

        PersistenceManager.saveLastPlayback(episode: currentEpisode, feedUrl: feedUrl)
    }
}
#endif
