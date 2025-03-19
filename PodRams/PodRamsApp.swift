import SwiftUI

@main
struct PodRamsApp: App {
    // Create a shared AudioPlayer instance at the app level with lazy initialization
    @StateObject private var audioPlayer = {
        // Initialize the audio player with error handling
        let player = AudioPlayer()
        print("AudioPlayer initialized successfully")
        return player
    }()
    
    // State for managing episodes and current episode index
    @State private var episodes: [PodcastEpisode] = []
    @State private var currentEpisodeIndex: Int?
    
    init() {
        // Set up any app-wide configurations
        print("PodRamsApp initializing...")
        
        #if DEBUG
        // We'll let the user run tests manually from the Debug menu instead
        // AppTests.runAllTests()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                appEpisodes: $episodes,
                appCurrentEpisodeIndex: $currentEpisodeIndex
            )
            .environmentObject(audioPlayer) // Provide the audio player as an environment object
            .onAppear {
                // Log for debugging launch issues
                print("App launched at \(Date())")
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
}
