import SwiftUI

@main
struct PodRamsApp: App {
    init() {
        #if DEBUG
        // We'll let the user run tests manually from the Debug menu instead
        // AppTests.runAllTests()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Log for debugging launch issues
                    print("App launched at \(Date())")
                }
        }
        .windowResizability(.contentSize)
        .commands {
            DebugCommands()
        }
    }
}
