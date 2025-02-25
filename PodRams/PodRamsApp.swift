import SwiftUI

@main
struct PodRamsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Log for debugging launch issues
                    print("App launched at \(Date())")
                }
        }
        .windowResizability(.contentSize)
    }
}
