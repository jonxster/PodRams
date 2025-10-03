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
        NSLocalizedString("Help.\(identifier).Title", comment: "Help section title")
    }

    var content: String {
        NSLocalizedString("Help.\(identifier).Content", comment: "Detailed help content for the section")
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
