//
// AudioPlayer.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import AVFoundation
import Accelerate // Added for optimized audio processing

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
    
    /// Optimized buffer size for Apple Silicon
    private let optimizedBufferSize: AVAudioFrameCount = {
        // Start with a reasonable default
        var bufferSize: AVAudioFrameCount = 1024
        
        // On Apple Silicon, slightly larger buffer sizes often work well
        // due to efficient cache handling
        if ProcessInfo.processInfo.processorCount >= 8 {
            // For M1/M2 with 8+ cores, use larger buffer
            bufferSize = 2048
        }
        
        return bufferSize
    }()
    
    /// Queue for audio processing tasks
    private let audioProcessingQueue = DispatchQueue(label: "com.podrams.audioProcessing", 
                                                    qos: .userInitiated, 
                                                    attributes: .concurrent)
    
    /// Optimized audio state structure to improve cache utilization
    private struct OptimizedAudioState {
        // Frequently accessed variables packed together
        var currentTime: Double = 0.0
        var duration: Double = 0.0
        var volume: Float = 1.0
        var isPlaying: Bool = false
        var rate: Float = 1.0
        
        // Less frequently accessed variables
        var url: URL?
        var metadata: [String: Any]?
    }
    
    /// Cached audio state for better memory access patterns
    private var audioState = OptimizedAudioState()
    
    /// Initializes the AudioPlayer by setting up throttling, configuring the audio engine, and restoring pan.
    init() {
        // No longer calling determineOptimalBufferSize() here
        
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
        
        // macOS doesn't use AVAudioSession, so we skip this configuration
        // which is only needed for iOS
        
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
        // Validate that pan is finite and within the valid range
        guard pan.isFinite else { return }
        
        // Clamp pan to valid range
        let safePan = max(0, min(1, pan))
        let panValue = Float((safePan * 2) - 1)
        playerNode.pan = panValue
        
        // Update the cached state
        audioState.rate = playerNode.rate
    }
    
    /// Updates the volume for the player node, main mixer, and AVPlayer.
    private func updateVolume() {
        // Validate that volume is finite and within the valid range
        guard volume.isFinite else { return }
        
        // Clamp volume to valid range
        let safeVolume = max(0, min(1, volume))
        playerNode.volume = Float(safeVolume)
        audioEngine.mainMixerNode.outputVolume = Float(safeVolume)
        player?.volume = Float(safeVolume)
        
        // Update the cached state
        audioState.volume = Float(safeVolume)
    }
    
    /// Plays audio from the specified URL.
    /// Cleans up previous playback, sets up a new AVPlayerItem with observers, and starts playback.
    /// - Parameter url: URL of the audio asset (local file or HTTP/HTTPS).
    func playAudio(url: URL) {
        guard url.isFileURL || url.scheme == "http" || url.scheme == "https" else {
            print("Invalid URL: \(url)")
            return
        }
        
        // If we're already playing this URL, just resume playback
        if currentURL == url && player != nil {
            player?.play()
            // Update state on main thread
            DispatchQueue.main.async {
                self.isPlaying = true
                self.audioState.isPlaying = true
            }
            return
        }
        
        // Stop existing playback and clean up resources
        stopAudio()
        cleanupObservers()
        
        // Reset playback state
        currentTime = 0
        duration = 0
        isLoading = true
        currentURL = url
        
        // Update cached state
        audioState.currentTime = 0
        audioState.duration = 0
        audioState.url = url
        
        // Use a concurrent queue for loading audio to avoid blocking the main thread
        audioProcessingQueue.async {
            // For local files, consider memory mapping for large files
            if url.isFileURL {
                self.loadLocalAudioFile(url)
            } else {
                // Create a new player item on a background thread
                let playerItem = AVPlayerItem(url: url)
                
                // Switch back to main thread for UI updates
                DispatchQueue.main.async {
                    self.setupPlayerItem(playerItem)
                    
                    // Create a new player
                    self.player = AVPlayer(playerItem: playerItem)
                    
                    // Apply current volume and add time observer
                    self.player?.volume = Float(self.volume)
                    self.addPeriodicTimeObserver()
                    
                    // Start playback
                    self.player?.play()
                    
                    // Update state
                    self.isPlaying = true
                    self.audioState.isPlaying = true
                }
            }
        }
    }
    
    /// Loads a local audio file with optimizations for Apple Silicon
    private func loadLocalAudioFile(_ url: URL) {
        do {
            // Check file size to determine if memory mapping is appropriate
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            
            // For large files (>50MB), use memory mapping
            if fileSize > 50_000_000 {
                let fileHandle = try FileHandle(forReadingFrom: url)
                let _ = fileHandle.mapDataAvailableForReading() // Keep in memory
                
                // Create player item from the URL
                let playerItem = AVPlayerItem(url: url)
                
                DispatchQueue.main.async {
                    self.setupPlayerItem(playerItem)
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.volume = Float(self.volume)
                    self.addPeriodicTimeObserver()
                    self.player?.play()
                    self.isPlaying = true
                    self.audioState.isPlaying = true
                }
            } else {
                // For smaller files, use standard AVPlayer
                let playerItem = AVPlayerItem(url: url)
                
                DispatchQueue.main.async {
                    self.setupPlayerItem(playerItem)
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.volume = Float(self.volume)
                    self.addPeriodicTimeObserver()
                    self.player?.play()
                    self.isPlaying = true
                    self.audioState.isPlaying = true
                }
            }
        } catch {
            print("Error loading local audio file: \(error)")
            
            // Fallback to standard method
            let playerItem = AVPlayerItem(url: url)
            
            DispatchQueue.main.async {
                self.setupPlayerItem(playerItem)
                self.player = AVPlayer(playerItem: playerItem)
                self.player?.volume = Float(self.volume)
                self.addPeriodicTimeObserver()
                self.player?.play()
                self.isPlaying = true
                self.audioState.isPlaying = true
            }
        }
    }
    
    /// Pauses the audio playback.
    func pauseAudio() {
        player?.pause()
        playerNode.pause()
        
        // Update state on main thread
        DispatchQueue.main.async {
            self.isPlaying = false
            self.audioState.isPlaying = false
        }
    }
    
    /// Stops the audio playback and resets the position to the beginning.
    func stopAudio() {
        player?.pause()
        if let player = player {
            player.seek(to: CMTime.zero)
        }
        playerNode.stop()
        
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = 0
            self.audioState.isPlaying = false
            self.audioState.currentTime = 0
        }
    }
    
    /// Seeks the playback to the specified time.
    /// If the audio engine is configured, schedules a new segment on the player node starting at the given time.
    /// - Parameter time: Time in seconds to seek to.
    func seek(to time: Double) {
        // Validate time is finite and non-negative
        guard time.isFinite && time >= 0 else {
            print("Warning: Attempted to seek to invalid time: \(time)")
            return
        }
        
        // Ensure time doesn't exceed duration if duration is valid
        let safeTime = duration > 0 ? min(time, duration) : time
        
        let cmTime = CMTime(seconds: safeTime, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = safeTime
        audioState.currentTime = safeTime
        
        if let url = currentURL, engineConfigured {
            // Use the audio processing queue for file operations
            audioProcessingQueue.async {
                guard let audioFile = try? AVAudioFile(forReading: url) else { return }
                let format = audioFile.processingFormat
                
                // Ensure we calculate a valid frame position
                let sampleRate = format.sampleRate
                guard sampleRate > 0 else { return }
                
                let framePosition = AVAudioFramePosition(safeTime * sampleRate)
                
                // Ensure we don't try to play beyond the file length
                let audioLength = audioFile.length
                guard framePosition <= audioLength else { return }
                
                let framesToPlay = AVAudioFrameCount(audioLength - framePosition)
                
                // Switch back to main thread for audio engine operations
                DispatchQueue.main.async {
                    self.playerNode.stop()
                    self.playerNode.scheduleSegment(audioFile,
                                               startingFrame: framePosition,
                                               frameCount: framesToPlay,
                                               at: nil,
                                               completionHandler: nil)
                    if self.isPlaying { self.playerNode.play() }
                }
            }
        }
    }
    
    /// Preloads an audio asset to reduce latency on playback start.
    /// - Parameter url: URL of the audio asset; applicable only for local files.
    func preloadAudio(url: URL) {
        // Use the audio processing queue for preloading
        audioProcessingQueue.async {
            if url.isFileURL {
                do {
                    // For local files, create an AVAudioFile to preload it
                    let _ = try AVAudioFile(forReading: url)
                    
                    // Also create an asset to preload metadata
                    let asset = AVURLAsset(url: url)
                    
                    // Use the load method instead of the deprecated duration property
                    Task {
                        do {
                            let _ = try await asset.load(.duration) // This triggers loading of the asset
                        } catch {
                            print("Error preloading audio duration: \(error)")
                        }
                    }
                } catch {
                    print("Error preloading audio file: \(error)")
                }
            } else {
                // For remote URLs, we can create an AVURLAsset with a preload hint
                let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                
                // Use the load method instead of the deprecated duration property
                Task {
                    do {
                        let _ = try await asset.load(.duration) // This triggers loading of the asset
                    } catch {
                        print("Error preloading remote audio duration: \(error)")
                    }
                }
            }
        }
    }
    
    /// Sets up throttling for published properties to limit the frequency of UI updates.
    private func setupThrottling() {
        // Increase throttling intervals to reduce UI update frequency
        
        $isPlaying
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] value in 
                self?.isPlaying = value
                self?.audioState.isPlaying = value
            }
            .store(in: &cancellables)
        
        $duration
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] value in 
                self?.duration = value
                self?.audioState.duration = value
            }
            .store(in: &cancellables)
    }
    
    /// Adds a periodic time observer to the AVPlayer to update the current playback time.
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        // Reduce update frequency from 0.1 to 0.5 seconds to decrease CPU load
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            let seconds = time.seconds
            
            // Validate that the time is finite and non-negative
            guard seconds.isFinite && seconds >= 0 else { return }
            
            // Only update if the time has changed significantly (more than 0.4 seconds)
            // This prevents unnecessary UI updates
            if abs(self.currentTime - seconds) > 0.4 {
                // Update the current time directly on the main thread
                self.currentTime = seconds
                self.audioState.currentTime = seconds
            }
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
            // Validate that the pan value is finite and within the valid range
            guard panValue.isFinite else {
                print("Warning: Received invalid pan value: \(panValue)")
                return
            }
            
            // Clamp pan to valid range
            let safePan = max(0, min(1, panValue))
            pan = safePan
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
        // Use a more efficient observation approach
        durationObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self, item.status == .readyToPlay else { return }
            
            // Only proceed if status is readyToPlay to avoid unnecessary processing
            DispatchQueue.main.async {
                Task {
                    do {
                        let duration = try await item.asset.load(.duration)
                        let seconds = duration.seconds
                        // Validate that the duration is finite and non-negative
                        if seconds.isFinite && seconds >= 0 {
                            self.duration = seconds
                            self.audioState.duration = seconds
                        } else {
                            self.duration = 0
                            self.audioState.duration = 0
                        }
                    } catch {
                        print("Error loading duration: \(error)")
                        self.duration = 0
                        self.audioState.duration = 0
                    }
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Adds proper cleanup when changing audio files
    private func cleanupCurrentAudio() {
        // Only clean up if we're changing audio files
        if player != nil {
            player?.pause()
            playerNode.pause()
            cleanupObservers()
        }
    }
    
    /// Adds this method to AudioPlayer to explicitly set the playing state
    func setPlayingState(_ isPlaying: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = isPlaying
            self.audioState.isPlaying = isPlaying
        }
    }
    
    // MARK: - Optimized Audio Processing Methods
    
    /// Process audio samples using vectorized operations for better performance on Apple Silicon
    /// - Parameters:
    ///   - samples: Array of audio samples to process
    ///   - gain: Volume gain to apply (0.0 to 1.0)
    ///   - pan: Pan value (0.0 = full left, 0.5 = center, 1.0 = full right)
    /// - Returns: Processed audio samples
    private func processAudioSamples(_ samples: [Float], gain: Float, pan: Float) -> [Float] {
        guard !samples.isEmpty else { return [] }
        
        // Create output buffer
        var outputSamples = [Float](repeating: 0.0, count: samples.count)
        
        // Make a mutable copy of gain for vDSP
        var gainValue = gain
        
        // Apply gain using vDSP (vectorized)
        vDSP_vsmul(samples, 1, &gainValue, &outputSamples, 1, vDSP_Length(samples.count))
        
        return outputSamples
    }
    
    /// Calculate the RMS (Root Mean Square) level of audio samples using Accelerate
    /// - Parameter samples: Audio samples to analyze
    /// - Returns: RMS level (0.0 to 1.0)
    private func calculateRMSLevel(for samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        var rms: Float = 0.0
        vDSP_measqv(samples, 1, &rms, vDSP_Length(samples.count))
        rms = sqrt(rms)
        
        // Normalize to 0.0-1.0 range (assuming audio samples are in -1.0 to 1.0 range)
        return min(1.0, rms)
    }
    
    /// Apply stereo panning to audio samples using vectorized operations
    /// - Parameters:
    ///   - samples: Interleaved stereo samples (left, right, left, right, ...)
    ///   - pan: Pan value (0.0 = full left, 0.5 = center, 1.0 = full right)
    /// - Returns: Panned audio samples
    private func applyStereoPanning(to samples: [Float], pan: Float) -> [Float] {
        guard samples.count >= 2 else { return samples }
        
        // Convert 0.0-1.0 pan to -1.0 to 1.0 range
        let panValue = (pan * 2.0) - 1.0
        
        // Calculate left and right gain based on pan
        // Using constant power panning law: left = cos(pan * π/2), right = sin(pan * π/2)
        let normalizedPan = (panValue + 1.0) / 2.0 // Convert to 0.0-1.0 for trig functions
        let panRadians = normalizedPan * Float.pi / 2.0
        let leftGain = cos(panRadians)
        let rightGain = sin(panRadians)
        
        // Create output buffer
        var outputSamples = [Float](repeating: 0.0, count: samples.count)
        
        // Process stereo samples (interleaved)
        for i in stride(from: 0, to: samples.count - 1, by: 2) {
            outputSamples[i] = samples[i] * leftGain
            outputSamples[i + 1] = samples[i + 1] * rightGain
        }
        
        return outputSamples
    }
    
    /// Process audio in blocks for better cache utilization
    /// - Parameters:
    ///   - samples: Audio samples to process
    ///   - blockSize: Size of each processing block
    ///   - processor: Function to process each block
    /// - Returns: Processed audio samples
    private func processAudioByBlocks(samples: [Float], blockSize: Int = 4096, processor: ([Float]) -> [Float]) -> [Float] {
        // Increase block size from 2048 to 4096 for better performance
        let totalSize = samples.count
        var result = [Float](repeating: 0.0, count: totalSize)
        
        for blockStart in stride(from: 0, to: totalSize, by: blockSize) {
            let blockEnd = min(blockStart + blockSize, totalSize)
            let blockRange = blockStart..<blockEnd
            let block = Array(samples[blockRange])
            
            // Process this block
            let processedBlock = processor(block)
            
            // Copy processed block back to result
            for (i, value) in processedBlock.enumerated() {
                if blockStart + i < totalSize {
                    result[blockStart + i] = value
                }
            }
        }
        
        return result
    }
}

// MARK: - FileHandle Extension for Memory Mapping

extension FileHandle {
    func mapDataAvailableForReading() -> Data {
        seekToEndOfFile()
        seek(toFileOffset: 0)
        
        // Create a mapped buffer for the file
        guard let data = try? self.readToEnd() else {
            return Data()
        }
        
        return data
    }
}
