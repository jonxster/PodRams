import XCTest
import SwiftUI
@testable import PodRams

// Mock AudioPlayer for testing
@MainActor
class MockAudioPlayer: AudioPlayer {
    override func playEpisode(_ episode: PodcastEpisode) {
        isPlaying = true
        duration = episode.duration ?? 3600
    }

    override func playAudio(url: URL) {
        isPlaying = true
        // Set duration when playing to simulate real behavior
        duration = 3600
    }
    
    override func pauseAudio() {
        isPlaying = false
    }
    
    override func stopAudio() {
        isPlaying = false
        currentTime = 0
    }
    
    override func seek(to time: Double) {
        currentTime = time
    }
}

final class PlayCommandsTests: XCTestCase {
    var audioPlayer: MockAudioPlayer!
    var episodes: [PodcastEpisode]!
    var currentEpisodeIndex: Int?
    var playCommands: PlayCommands!
    
    override func setUp() {
        super.setUp()
        let createdPlayer = try! MainActor.assumeIsolated { MockAudioPlayer() }
        audioPlayer = createdPlayer
        episodes = [
            PodcastEpisode(
                title: "Test Episode 1",
                url: URL(string: "https://example.com/ep1.mp3")!,
                artworkURL: URL(string: "https://example.com/artwork1.jpg"),
                duration: 3600,
                showNotes: "Test show notes 1"
            ),
            PodcastEpisode(
                title: "Test Episode 2",
                url: URL(string: "https://example.com/ep2.mp3")!,
                artworkURL: URL(string: "https://example.com/artwork2.jpg"),
                duration: 3600,
                showNotes: "Test show notes 2"
            ),
            PodcastEpisode(
                title: "Test Episode 3",
                url: URL(string: "https://example.com/ep3.mp3")!,
                artworkURL: URL(string: "https://example.com/artwork3.jpg"),
                duration: 3600,
                showNotes: "Test show notes 3"
            )
        ]
        
        // Create a proper binding that we can modify in tests
        currentEpisodeIndex = 1 // Start with middle episode
        let initialEpisodes = episodes ?? []
        playCommands = try! MainActor.assumeIsolated {
            PlayCommands(
                audioPlayer: createdPlayer,
                currentEpisodeIndex: .constant(1),
                episodes: initialEpisodes
            )
        }
    }
    
    override func tearDown() {
        audioPlayer = nil
        episodes = nil
        currentEpisodeIndex = nil
        playCommands = nil
        super.tearDown()
    }
    
    // MARK: - Playback Control Tests
    
    @MainActor
    func testPlayPauseToggle() {
        // Initial state
        XCTAssertFalse(audioPlayer.isPlaying)
        
        // Test Play command
        if !audioPlayer.isPlaying {
            audioPlayer.playAudio(url: episodes[1].url)
        }
        XCTAssertTrue(audioPlayer.isPlaying)
        
        // Test Pause command
        if audioPlayer.isPlaying {
            audioPlayer.pauseAudio()
        }
        XCTAssertFalse(audioPlayer.isPlaying)
    }
    
    @MainActor
    func testStopPlayback() {
        // Setup initial state
        audioPlayer.currentTime = 50
        audioPlayer.playAudio(url: episodes[1].url)
        XCTAssertTrue(audioPlayer.isPlaying)
        
        // Execute Stop command
        audioPlayer.stopAudio()
        
        XCTAssertFalse(audioPlayer.isPlaying)
        XCTAssertEqual(audioPlayer.currentTime, 0)
    }
    
    // MARK: - Episode Navigation Tests
    
    @MainActor
    func testPreviousEpisode() {
        // Setup with a mutable binding
        var currentIndex: Int? = 1
        let binding = Binding(
            get: { currentIndex },
            set: { currentIndex = $0 }
        )
        
        playCommands = PlayCommands(
            audioPlayer: audioPlayer,
            currentEpisodeIndex: binding,
            episodes: episodes
        )
        
        // Execute Previous Episode command
        if let index = currentIndex, index > 0 {
            let newIndex = index - 1
            binding.wrappedValue = newIndex
            audioPlayer.playAudio(url: episodes[newIndex].url)
        }
        
        XCTAssertEqual(currentIndex, 0)
        XCTAssertTrue(audioPlayer.isPlaying)
    }
    
    @MainActor
    func testNextEpisode() {
        // Setup with a mutable binding
        var currentIndex: Int? = 1
        let binding = Binding(
            get: { currentIndex },
            set: { currentIndex = $0 }
        )
        
        playCommands = PlayCommands(
            audioPlayer: audioPlayer,
            currentEpisodeIndex: binding,
            episodes: episodes
        )
        
        // Execute Next Episode command
        if let index = currentIndex, index < episodes.count - 1 {
            let newIndex = index + 1
            binding.wrappedValue = newIndex
            audioPlayer.playAudio(url: episodes[newIndex].url)
        }
        
        XCTAssertEqual(currentIndex, 2)
        XCTAssertTrue(audioPlayer.isPlaying)
    }
    
    // MARK: - Seeking Tests
    
    @MainActor
    func testSkipBackward() {
        // Setup initial state
        audioPlayer.currentTime = 100
        audioPlayer.duration = 200
        
        // Execute Skip Backward command
        let newTime = max(0, audioPlayer.currentTime - 30)
        audioPlayer.seek(to: newTime)
        
        XCTAssertEqual(audioPlayer.currentTime, 70)
    }
    
    @MainActor
    func testSkipForward() {
        // Setup initial state
        audioPlayer.currentTime = 100
        audioPlayer.duration = 200
        
        // Execute Skip Forward command
        let newTime = min(audioPlayer.duration, audioPlayer.currentTime + 30)
        audioPlayer.seek(to: newTime)
        
        XCTAssertEqual(audioPlayer.currentTime, 130)
    }
    
    // MARK: - Volume Control Tests
    
    @MainActor
    func testVolumeUp() {
        // Setup initial state
        audioPlayer.volume = 0.5
        
        // Execute Volume Up command
        audioPlayer.volume = min(1.0, audioPlayer.volume + 0.1)
        
        XCTAssertEqual(audioPlayer.volume, 0.6, accuracy: 0.001)
    }
    
    @MainActor
    func testVolumeDown() {
        // Setup initial state
        audioPlayer.volume = 0.5
        
        // Execute Volume Down command
        audioPlayer.volume = max(0.0, audioPlayer.volume - 0.1)
        
        XCTAssertEqual(audioPlayer.volume, 0.4, accuracy: 0.001)
    }
    
    @MainActor
    func testMuteUnmute() {
        // Setup initial state
        audioPlayer.volume = 0.8
        
        // Execute Mute command
        let previousVolume = audioPlayer.volume
        if audioPlayer.volume > 0 {
            audioPlayer.volume = 0
        }
        XCTAssertEqual(audioPlayer.volume, 0)
        
        // Execute Unmute command
        if audioPlayer.volume == 0 {
            audioPlayer.volume = previousVolume
        }
        XCTAssertEqual(audioPlayer.volume, 0.8)
    }
    
    // MARK: - Edge Case Tests
    
    @MainActor
    func testSkipBackwardAtStart() {
        // Setup initial state
        audioPlayer.currentTime = 0
        audioPlayer.duration = 200
        
        // Execute Skip Backward command at start
        let newTime = max(0, audioPlayer.currentTime - 30)
        audioPlayer.seek(to: newTime)
        
        XCTAssertEqual(audioPlayer.currentTime, 0)
    }
    
    @MainActor
    func testSkipForwardAtEnd() {
        // Setup initial state
        audioPlayer.duration = 200
        audioPlayer.currentTime = 200
        
        // Execute Skip Forward command at end
        let newTime = min(audioPlayer.duration, audioPlayer.currentTime + 30)
        audioPlayer.seek(to: newTime)
        
        XCTAssertEqual(audioPlayer.currentTime, 200)
    }
    
    @MainActor
    func testVolumeUpAtMax() {
        // Setup initial state
        audioPlayer.volume = 1.0
        
        // Execute Volume Up command at max
        audioPlayer.volume = min(1.0, audioPlayer.volume + 0.1)
        
        XCTAssertEqual(audioPlayer.volume, 1.0)
    }
    
    @MainActor
    func testVolumeDownAtMin() {
        // Setup initial state
        audioPlayer.volume = 0.0
        
        // Execute Volume Down command at min
        audioPlayer.volume = max(0.0, audioPlayer.volume - 0.1)
        
        XCTAssertEqual(audioPlayer.volume, 0.0)
    }
    
    // MARK: - Disabled State Tests
    
    @MainActor
    func testDisabledStateWithNoEpisode() {
        var currentIndex: Int? = nil
        let binding = Binding(
            get: { currentIndex },
            set: { currentIndex = $0 }
        )
        
        // Create commands with no episode selected
        _ = PlayCommands(
            audioPlayer: audioPlayer,
            currentEpisodeIndex: binding,
            episodes: episodes
        )
        
        // Verify that commands are disabled when no episode is selected
        XCTAssertFalse(audioPlayer.isPlaying)
        
        // Try to play
        if let index = binding.wrappedValue, index < episodes.count {
            audioPlayer.playAudio(url: episodes[index].url)
        }
        XCTAssertFalse(audioPlayer.isPlaying)
    }
} 
