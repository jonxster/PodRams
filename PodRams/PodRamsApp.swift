import SwiftUI

@main
struct PodRamsApp: App {
    // Create a shared AudioPlayer instance at the app level
    @StateObject private var audioPlayer = AudioPlayer()
    
    init() {
        #if DEBUG
        // We'll let the user run tests manually from the Debug menu instead
        // AppTests.runAllTests()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer) // Provide the audio player as an environment object
                .onAppear {
                    // Log for debugging launch issues
                    print("App launched at \(Date())")
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            DebugCommands()
        }
    }
}
