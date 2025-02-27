//
// AudioPlayer.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import AVFoundation

/// Manages audio playback using AVPlayer and AVAudioEngine.
/// Publishes playback state and allows control over play, pause, stop, seek, volume, and pan.
class AudioPlayer: ObservableObject {
    /// Indicates whether audio is currently playing.
    @Published var isPlaying = false
    /// Indicates if audio is in the process of loading.
    @Published var isLoading = false
    /// Current playback time in seconds.
    @Published var currentTime: Double = 0
    /// Total duration of the audio in seconds.
    @Published var duration: Double = 0
    /// Volume level (0.0 to 1.0). Changing this updates the player and mixer.
    @Published var volume: Double = 0.5 {
        didSet { updateVolume() }
    }
    /// Pan value from 0 (full left) to 1 (full right); 0.5 is centered.
    /// Updates the audio engine and saves the setting.
    @Published var pan: Double = 0.5 {
        didSet {
            updatePan()
            UserDefaults.standard.set(pan, forKey: "audioPan")
        }
    }
    
    /// Audio engine for processing audio.
    private let audioEngine = AVAudioEngine()
    /// Audio node for routing playback through the audio engine.
    private let playerNode = AVAudioPlayerNode()
    
    /// AVPlayer used for audio playback.
    private var player: AVPlayer?
    /// Token for the AVPlayer's time observer.
    private var timeObserverToken: Any?
    /// Observes changes in the player's status, especially for duration.
    private var durationObserver: NSKeyValueObservation?
    /// Set of Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()
    /// URL of the currently playing audio.
    private var currentURL: URL?
    /// Flag indicating whether the audio engine was successfully configured.
    private var engineConfigured = false
    
    /// Initializes the AudioPlayer by setting up throttling, configuring the audio engine, and restoring pan.
    init() {
        setupThrottling()
        setupAudioEngine()
        
        // Restore saved pan value if available.
        if let savedPan = UserDefaults.standard.object(forKey: "audioPan") as? Double {
            pan = savedPan
        }
        
        // Listen for external notifications to change pan.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handlePanChange),
                                               name: .audioPanChanged,
                                               object: nil)
    }
    
    /// Configures the audio engine by attaching and connecting the player node.
    /// Also starts the engine and applies initial volume and pan settings.
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let format = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        
        updatePan()
        updateVolume()
        
        do {
            try audioEngine.start()
            engineConfigured = true
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    /// Updates the pan for the player node.
    /// Converts the 0...1 range (with 0.5 as center) to the -1...1 range required by AVAudioPlayerNode.
    private func updatePan() {
        let panValue = Float((pan * 2) - 1)
        playerNode.pan = panValue
        print("Player node pan set to: \(panValue)")
    }
    
    /// Updates the volume for the player node, main mixer, and AVPlayer.
    private func updateVolume() {
        playerNode.volume = Float(volume)
        audioEngine.mainMixerNode.outputVolume = Float(volume)
        player?.volume = Float(volume)
        print("Volume set to: \(volume)")
    }
    
    /// Plays audio from the specified URL.
    /// Cleans up previous playback, sets up a new AVPlayerItem with observers, and starts playback.
    /// - Parameter url: URL of the audio asset (local file or HTTP/HTTPS).
    func playAudio(url: URL) {
        guard url.isFileURL || url.scheme == "http" || url.scheme == "https" else {
            print("Invalid URL: \(url)")
            return
        }
        
        print("Playing audio from URL: \(url)")
        
        // Stop existing playback and remove any observers.
        stopAudio()
        cleanupObservers()
        
        // Reset playback state.
        isPlaying = false
        currentTime = 0
        duration = 0
        isLoading = true
        currentURL = url
        
        // Create a new player item and set up its status observer.
        let playerItem = AVPlayerItem(url: url)
        setupPlayerItem(playerItem)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        
        // Apply current volume, add a periodic observer, and start playback.
        player?.volume = Float(volume)
        addPeriodicTimeObserver()
        player?.play()
        isPlaying = true
        isLoading = false
    }
    
    /// Placeholder method for playing audio through the audio engine.
    /// Currently, AVPlayer is used for both remote and local files.
    private func playThroughAudioEngine(url: URL) {
        player?.volume = Float(volume)
        player?.play()
        isPlaying = true
    }
    
    /// Pauses the audio playback.
    func pauseAudio() {
        player?.pause()
        playerNode.pause()
        isPlaying = false
    }
    
    /// Stops the audio playback and resets the position to the beginning.
    func stopAudio() {
        player?.pause()
        player?.seek(to: .zero)
        playerNode.stop()
        isPlaying = false
    }
    
    /// Seeks the playback to the specified time.
    /// If the audio engine is configured, schedules a new segment on the player node starting at the given time.
    /// - Parameter time: Time in seconds to seek to.
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
        
        if let url = currentURL, engineConfigured {
            playerNode.stop()
            guard let audioFile = try? AVAudioFile(forReading: url) else { return }
            let format = audioFile.processingFormat
            let framePosition = AVAudioFramePosition(time * format.sampleRate)
            let framesToPlay = AVAudioFrameCount(audioFile.length - framePosition)
            playerNode.scheduleSegment(audioFile,
                                         startingFrame: framePosition,
                                         frameCount: framesToPlay,
                                         at: nil,
                                         completionHandler: nil)
            if isPlaying { playerNode.play() }
        }
    }
    
    /// Preloads an audio asset to reduce latency on playback start.
    /// - Parameter url: URL of the audio asset; applicable only for local files.
    func preloadAudio(url: URL) {
        print("Preloading asset for \(url)")
        if url.isFileURL { _ = try? AVAudioFile(forReading: url) }
    }
    
    /// Sets up throttling for published properties to limit the frequency of UI updates.
    private func setupThrottling() {
        $currentTime
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] time in self?.currentTime = time }
            .store(in: &cancellables)
        
        $isPlaying
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] value in self?.isPlaying = value }
            .store(in: &cancellables)
        
        $duration
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] value in self?.duration = value }
            .store(in: &cancellables)
    }
    
    /// Adds a periodic time observer to the AVPlayer to update the current playback time.
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    /// Removes the periodic time observer and invalidates the duration observer.
    private func cleanupObservers() {
        if let player = player, let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        durationObserver?.invalidate()
        durationObserver = nil
    }
    
    /// Handles external notifications to update the pan setting.
    /// - Parameter notification: Notification containing a new pan value.
    @objc private func handlePanChange(_ notification: Notification) {
        if let panValue = notification.userInfo?["pan"] as? Double {
            pan = panValue
        }
    }
    
    /// Cleans up resources on deinitialization.
    /// Removes observers, stops playback, and resets the audio engine.
    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupObservers()
        player?.pause()
        player = nil
        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()
        cancellables.removeAll()
    }
    
    /// Sets up an observer on the AVPlayerItem to monitor its status.
    /// Updates the audio duration when the item is ready to play.
    /// - Parameter playerItem: The AVPlayerItem to observe.
    private func setupPlayerItem(_ playerItem: AVPlayerItem) {
        durationObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    self.duration = item.duration.seconds
                    self.isLoading = false
                case .failed:
                    print("Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                    self.isLoading = false
                default:
                    break
                }
            }
        }
    }
}
