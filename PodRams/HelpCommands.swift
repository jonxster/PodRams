import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif

/// Provides help documentation accessible via the app's menu.
struct HelpCommands: Commands {
    var body: some Commands {
        // Replace the default Help menu with our custom help items
        CommandGroup(replacing: .help) {
            // Getting Started section
            Button(action: { showHelp(section: .gettingStarted) }) {
                Text(HelpSection.gettingStarted.title)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])

            Divider()

            // Playback Controls section
            Button(action: { showHelp(section: .playbackControls) }) {
                Text(HelpSection.playbackControls.title)
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])

            // Episode Management section
            Button(action: { showHelp(section: .episodeManagement) }) {
                Text(HelpSection.episodeManagement.title)
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])

            // Podcast Management section
            Button(action: { showHelp(section: .podcastManagement) }) {
                Text(HelpSection.podcastManagement.title)
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])

            Divider()

            // Keyboard Shortcuts section
            Button(action: { showHelp(section: .keyboardShortcuts) }) {
                Text(HelpSection.keyboardShortcuts.title)
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])

            // About section
            Button(action: { showHelp(section: .about) }) {
                Text(HelpSection.about.title)
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
enum HelpSection: CaseIterable, Hashable {
    case gettingStarted
    case playbackControls
    case episodeManagement
    case podcastManagement
    case keyboardShortcuts
    case about

    private var identifier: String {
        switch self {
        case .gettingStarted: return "GettingStarted"
        case .playbackControls: return "PlaybackControls"
        case .episodeManagement: return "EpisodeManagement"
        case .podcastManagement: return "PodcastManagement"
        case .keyboardShortcuts: return "KeyboardShortcuts"
        case .about: return "About"
        }
    }

    var localizedTitleKey: LocalizedStringKey {
        LocalizedStringKey("Help.\(identifier).Title")
    }

    var title: String {
        HelpLocalization.string("Help.\(identifier).Title")
    }

    var content: String {
        HelpLocalization.string("Help.\(identifier).Content")
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

private enum HelpLocalization {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }()

    static func string(_ key: String) -> String {
        let localized = bundle.localizedString(forKey: key, value: key, table: nil)
        if localized == key, let fallback = fallbackStrings[key] {
            return fallback
        }
        return localized
    }

    private static let fallbackStrings: [String: String] = [
        "Help.GettingStarted.Title": "Getting Started",
        "Help.GettingStarted.Content": """
Welcome to PodRams!

To get started:
1. Click the search icon (🔍) to find podcasts.
2. Subscribe to shows you like using the subscribe button.
3. Download episodes or stream them directly.
4. Build a listening queue with the cue system.
5. Mark favorite podcasts for quick access.

Use the toolbar icons for quick access to common functions.
""",
        "Help.PlaybackControls.Title": "Playback Controls",
        "Help.PlaybackControls.Content": """
Playback controls:

• Play/Pause (⌘P): Toggle playback of the current episode.
• Stop (⌘S): Stop playback and reset position.
• Previous/Next Episode (⌘←/→): Navigate between episodes.
• Skip Back/Forward (⌥⌘←/→): Jump 30 seconds.
• Volume Up/Down (⌘↑/↓): Adjust volume.
• Mute/Unmute (⌘M): Toggle audio.

You can access the same controls from the Play menu and the keyboard shortcuts listed above.
""",
        "Help.EpisodeManagement.Title": "Episode Management",
        "Help.EpisodeManagement.Content": """
Episode management:

• Download episodes for offline listening.
• Export episodes as audio files.
• Share episodes with friends.
• Add episodes to your cue (playlist).
• Reorder episodes.
• View episode details.
• Track download progress.
• Delete downloaded episodes.

Open the context menu (•••) on any episode to see these actions.
""",
        "Help.PodcastManagement.Title": "Podcast Management",
        "Help.PodcastManagement.Content": """
Podcast management:

• Subscribe to podcasts to receive new episodes.
• Add podcasts to favorites for quick access.
• View podcast details.
• Manage your subscriptions.
• Search for new podcasts.
• Import/Export subscription lists.

Toolbar icons let you jump directly to these management screens.
""",
        "Help.KeyboardShortcuts.Title": "Keyboard Shortcuts",
        "Help.KeyboardShortcuts.Content": """
Keyboard shortcuts:

Playback:
• ⌘P — Play/Pause
• ⌘S — Stop
• ⌘← — Previous episode
• ⌘→ — Next episode
• ⌥⌘← — Skip back 30 s
• ⌥⌘→ — Skip forward 30 s
• ⌘↑ — Volume up
• ⌘↓ — Volume down
• ⌘M — Mute/Unmute

Navigation:
• ⌘F — Search
• ⌘C — Toggle cue
• Space — Play/Pause

Help:
• ⇧⌘1 — Getting Started
• ⇧⌘2 — Playback Controls
• ⇧⌘3 — Episode Management
• ⇧⌘4 — Podcast Management
• ⇧⌘5 — Keyboard Shortcuts
• ⇧⌘6 — About
""",
        "Help.About.Title": "About PodRams",
        "Help.About.Content": """
PodRams — A modern macOS podcast player.

Highlights:
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
    ]
}
