import XCTest
import SwiftUI
@testable import PodRams

final class HelpCommandsTests: XCTestCase {
    var helpCommands: HelpCommands!
    
    override func setUp() {
        super.setUp()
        helpCommands = HelpCommands()
    }
    
    override func tearDown() {
        helpCommands = nil
        super.tearDown()
    }
    
    // MARK: - Help Section Tests
    
    func testHelpSectionTitles() {
        // Test that all help section titles match their raw values
        XCTAssertEqual(HelpSection.gettingStarted.title, "Getting Started")
        XCTAssertEqual(HelpSection.playbackControls.title, "Playback Controls")
        XCTAssertEqual(HelpSection.episodeManagement.title, "Episode Management")
        XCTAssertEqual(HelpSection.podcastManagement.title, "Podcast Management")
        XCTAssertEqual(HelpSection.keyboardShortcuts.title, "Keyboard Shortcuts")
        XCTAssertEqual(HelpSection.about.title, "About PodRams")
    }
    
    func testHelpSectionContent() {
        // Test that all help sections have non-empty content
        XCTAssertFalse(HelpSection.gettingStarted.content.isEmpty)
        XCTAssertFalse(HelpSection.playbackControls.content.isEmpty)
        XCTAssertFalse(HelpSection.episodeManagement.content.isEmpty)
        XCTAssertFalse(HelpSection.podcastManagement.content.isEmpty)
        XCTAssertFalse(HelpSection.keyboardShortcuts.content.isEmpty)
        XCTAssertFalse(HelpSection.about.content.isEmpty)
    }
    
    func testGettingStartedContent() {
        let content = HelpSection.gettingStarted.content
        // Test that getting started content includes essential steps
        XCTAssertTrue(content.contains("Welcome to PodRams"))
        XCTAssertTrue(content.contains("search icon"))
        XCTAssertTrue(content.contains("Subscribe"))
        XCTAssertTrue(content.contains("Download"))
        XCTAssertTrue(content.contains("cue system"))
        XCTAssertTrue(content.contains("favorite"))
    }
    
    func testPlaybackControlsContent() {
        let content = HelpSection.playbackControls.content
        // Test that playback controls content includes all shortcuts
        XCTAssertTrue(content.contains("Play/Pause"))
        XCTAssertTrue(content.contains("Stop"))
        XCTAssertTrue(content.contains("Previous/Next Episode"))
        XCTAssertTrue(content.contains("Skip Back/Forward"))
        XCTAssertTrue(content.contains("Volume Up/Down"))
        XCTAssertTrue(content.contains("Mute/Unmute"))
    }
    
    func testEpisodeManagementContent() {
        let content = HelpSection.episodeManagement.content
        // Test that episode management content includes key features
        XCTAssertTrue(content.contains("Download episodes"))
        XCTAssertTrue(content.contains("Add episodes to your cue"))
        XCTAssertTrue(content.contains("Reorder episodes"))
        XCTAssertTrue(content.contains("View episode details"))
        XCTAssertTrue(content.contains("Track download progress"))
        XCTAssertTrue(content.contains("Delete downloaded episodes"))
    }
    
    func testPodcastManagementContent() {
        let content = HelpSection.podcastManagement.content
        // Test that podcast management content includes key features
        XCTAssertTrue(content.contains("Subscribe to podcasts"))
        XCTAssertTrue(content.contains("Add podcasts to favorites"))
        XCTAssertTrue(content.contains("View podcast details"))
        XCTAssertTrue(content.contains("Manage your subscriptions"))
        XCTAssertTrue(content.contains("Search for new podcasts"))
        XCTAssertTrue(content.contains("Import/Export"))
    }
    
    func testKeyboardShortcutsContent() {
        let content = HelpSection.keyboardShortcuts.content
        // Test that keyboard shortcuts content includes all shortcuts
        XCTAssertTrue(content.contains("⌘P"))
        XCTAssertTrue(content.contains("⌘S"))
        XCTAssertTrue(content.contains("⌘←"))
        XCTAssertTrue(content.contains("⌘→"))
        XCTAssertTrue(content.contains("⌥⌘←"))
        XCTAssertTrue(content.contains("⌥⌘→"))
        XCTAssertTrue(content.contains("⌘↑"))
        XCTAssertTrue(content.contains("⌘↓"))
        XCTAssertTrue(content.contains("⌘M"))
        XCTAssertTrue(content.contains("⌘F"))
        XCTAssertTrue(content.contains("⌘C"))
        XCTAssertTrue(content.contains("Space"))
    }
    
    func testAboutContent() {
        let content = HelpSection.about.content
        // Test that about content includes app features
        XCTAssertTrue(content.contains("PodRams"))
        XCTAssertTrue(content.contains("Smart Playback"))
        XCTAssertTrue(content.contains("Download Management"))
        XCTAssertTrue(content.contains("Cue System"))
        XCTAssertTrue(content.contains("Search Integration"))
        XCTAssertTrue(content.contains("Favorites"))
        XCTAssertTrue(content.contains("Subscriptions"))
        XCTAssertTrue(content.contains("Audio Controls"))
        XCTAssertTrue(content.contains("Persistence"))
        XCTAssertTrue(content.contains("Artwork Support"))
        XCTAssertTrue(content.contains("Audio Output Selection"))
    }
    
    // MARK: - Help Content View Tests
    
    func testHelpContentView() {
        // Test that the help content view can be created with each section
        for section in [
            HelpSection.gettingStarted,
            HelpSection.playbackControls,
            HelpSection.episodeManagement,
            HelpSection.podcastManagement,
            HelpSection.keyboardShortcuts,
            HelpSection.about
        ] {
            let view = HelpContentView(section: section)
            XCTAssertNotNil(view)
        }
    }
} 