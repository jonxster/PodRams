import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Provides help documentation accessible via the app's menu.
struct HelpCommands: Commands {
    var body: some Commands {
        // Replace the default Help menu with our custom help items
        CommandGroup(replacing: .help) {
            // Getting Started section
            Button("Getting Started") {
                showHelp(section: .gettingStarted)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            
            Divider()
            
            // Playback Controls section
            Button("Playback Controls") {
                showHelp(section: .playbackControls)
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])
            
            // Episode Management section
            Button("Episode Management") {
                showHelp(section: .episodeManagement)
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
            
            // Podcast Management section
            Button("Podcast Management") {
                showHelp(section: .podcastManagement)
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
            
            Divider()
            
            // Keyboard Shortcuts section
            Button("Keyboard Shortcuts") {
                showHelp(section: .keyboardShortcuts)
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
            
            // About section
            Button("About PodRams") {
                showHelp(section: .about)
            }
            .keyboardShortcut("6", modifiers: [.command, .shift])
        }
    }
    
    /// Shows help content for the specified section
    private func showHelp(section: HelpSection) {
        #if os(macOS)
        HelpWindowManager.shared.open(section: section)
        #endif
    }
}

/// Represents different sections of the help documentation
enum HelpSection: String {
    case gettingStarted = "Getting Started"
    case playbackControls = "Playback Controls"
    case episodeManagement = "Episode Management"
    case podcastManagement = "Podcast Management"
    case keyboardShortcuts = "Keyboard Shortcuts"
    case about = "About PodRams"
    
    var title: String { rawValue }
    
    var content: String {
        switch self {
        case .gettingStarted:
            return """
            Welcome to PodRams!
            
            To get started:
            1. Click the search icon (🔍) to find podcasts
            2. Subscribe to podcasts you like using the subscribe button
            3. Download episodes or stream them directly
            4. Create playlists using the cue system
            5. Mark your favorite podcasts for quick access
            
            Use the toolbar icons for quick access to common functions.
            """
            
        case .playbackControls:
            return """
            Playback Controls:
            
            • Play/Pause (⌘P): Toggle playback of current episode
            • Stop (⌘S): Stop playback and reset position
            • Previous/Next Episode (⌘←/→): Navigate between episodes
            • Skip Back/Forward (⌥⌘←/→): Skip 30 seconds
            • Volume Up/Down (⌘↑/↓): Adjust volume
            • Mute/Unmute (⌘M): Toggle audio
            
            The playback controls are available in the Play menu and through keyboard shortcuts.
            """
            
        case .episodeManagement:
            return """
            Episode Management:
            
            • Download episodes for offline listening
            • Add episodes to your cue (playlist)
            • Reorder episodes in the cue by dragging
            • View episode details and show notes
            • Track download progress
            • Delete downloaded episodes
            
            Access episode options through the context menu (•••).
            """
            
        case .podcastManagement:
            return """
            Podcast Management:
            
            • Subscribe to podcasts to receive new episodes
            • Add podcasts to favorites for quick access
            • View podcast details and episode list
            • Manage your subscriptions
            • Search for new podcasts
            • Import/Export subscriptions
            
            Use the toolbar icons for podcast management functions.
            """
            
        case .keyboardShortcuts:
            return """
            Keyboard Shortcuts:
            
            Playback:
            • ⌘P - Play/Pause
            • ⌘S - Stop
            • ⌘← - Previous Episode
            • ⌘→ - Next Episode
            • ⌥⌘← - Skip Back 30s
            • ⌥⌘→ - Skip Forward 30s
            • ⌘↑ - Volume Up
            • ⌘↓ - Volume Down
            • ⌘M - Mute/Unmute
            
            Navigation:
            • ⌘F - Search
            • ⌘C - Toggle Cue
            • Space - Play/Pause
            
            Help:
            • ⇧⌘1 - Getting Started
            • ⇧⌘2 - Playback Controls
            • ⇧⌘3 - Episode Management
            • ⇧⌘4 - Podcast Management
            • ⇧⌘5 - Keyboard Shortcuts
            • ⇧⌘6 - About
            """
            
        case .about:
            return """
            PodRams - A Modern macOS Podcast Player
            
            Features:
            • Smart Playback
            • Download Management
            • Cue System
            • Search Integration
            • Favorites
            • Subscriptions
            • Audio Controls
            • Persistence
            • Artwork Support
            • Audio Output Selection
            
            Built with SwiftUI for macOS 11.0 and later.
            """
        }
    }
}

/// View for displaying help content
struct HelpContentView: View {
    let section: HelpSection
    
    var body: some View {
        ScrollView {
            Text(section.content)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if os(macOS)
/// Manages the lifecycle of help windows to avoid premature deallocation crashes.
@MainActor
final class HelpWindowManager: NSObject, NSWindowDelegate {
    static let shared = HelpWindowManager()

    private var windows: [HelpSection: NSWindow] = [:]

    func open(section: HelpSection) {
        if let existing = windows[section] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: HelpContentView(section: section))
        controller.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let window = NSWindow(
            contentRect: controller.view.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.title = section.title
        window.contentViewController = controller
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        windows[section] = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let entry = windows.first(where: { $0.value == window }) {
            windows.removeValue(forKey: entry.key)
        }
    }
}
#endif
