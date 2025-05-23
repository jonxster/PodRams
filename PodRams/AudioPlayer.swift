//
// AudioPlayer.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import AVFoundation
import Accelerate // Added for optimized audio processing
import AudioToolbox
import CoreMedia

/// Manages audio playback using AVPlayer and AVAudioEngine.
/// Publishes playback state and allows control over play, pause, stop, seek, volume, and pan.
/// Optimized for reduced CPU usage while maintaining full functionality.
@MainActor // Ensure all methods and properties are accessed on the main actor
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
        didSet { 
            // Debounce volume changes to reduce CPU overhead
            volumeUpdateTask?.cancel()
            volumeUpdateTask = Task { 
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
                await updateVolume() 
            }
        }
    }
    /// Pan value from 0 (full left) to 1 (full right); 0.5 is centered.
    /// Updates the audio engine and saves the setting.
    @Published var pan: Double = 0.5 {
        didSet {
            // Debounce pan changes to reduce CPU overhead
            panUpdateTask?.cancel()
            panUpdateTask = Task {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
                await updatePan()
                UserDefaults.standard.set(pan, forKey: "audioPan")
            }
        }
    }
    
    /// Audio engine for processing audio.
    private let audioEngine = AVAudioEngine()
    /// Audio node for routing playback through the audio engine.
    private let playerNode = AVAudioPlayerNode()
    
    /// AVPlayer used for audio playback.
    private var player: AVPlayer?
    /// Tap for streaming audio pan adjustments
    /// Stored as a CF tap reference; ownership is managed by the audio mix property.
    private var panTap: MTAudioProcessingTap?
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
    
    // CPU Optimization: Debouncing tasks
    private var volumeUpdateTask: Task<Void, Error>?
    private var panUpdateTask: Task<Void, Error>?
    private var timeUpdateTask: Task<Void, Error>?
    
    /// Optimized buffer size for reduced CPU overhead
    private let optimizedBufferSize: AVAudioFrameCount = {
        // Increase buffer size to reduce callback frequency and CPU overhead
        // Larger buffers = fewer callbacks = lower CPU usage
        var bufferSize: AVAudioFrameCount = 2048
        
        // For podcast playback, we can use larger buffers since latency is less critical
        if ProcessInfo.processInfo.processorCount >= 8 {
            // For M1/M2 with 8+ cores, use larger buffer for efficiency
            bufferSize = 4096
        }
        
        return bufferSize
    }()
    
    /// Queue for audio processing tasks - using serial queue to reduce thread contention
    private let audioProcessingQueue = DispatchQueue(label: "com.podrams.audioProcessing", 
                                                    qos: .utility) // Reduced QoS to save CPU
    
    /// Audio format cache to avoid repeated format calculations
    private var cachedAudioFormat: AVAudioFormat?
    
    /// Optimized audio state structure to improve cache utilization
    private struct OptimizedAudioState {
        // Frequently accessed variables packed together
        var currentTime: Double = 0.0
        var duration: Double = 0.0
        var volume: Float = 1.0
        var isPlaying: Bool = false
        var rate: Float = 1.0
        var isLoading: Bool = false
        var lastPanValue: Float = 0.5 // Cache last pan value to avoid unnecessary updates
        
        // Less frequently accessed variables
        var url: URL?
        var metadata: [String: Any]?
    }
    
    /// Cached audio state for better memory access patterns
    private var audioState = OptimizedAudioState()
    
    /// CPU Optimization: Batch property updates to reduce UI refresh frequency
    private var pendingPropertyUpdates: Set<String> = []
    private var propertyUpdateTimer: Timer?
    
    /// Initializes the AudioPlayer by setting up throttling, configuring the audio engine, and restoring pan.
    init() {
        // Initialize properties before any operations
        engineConfigured = false
        
        // Setup optimized throttling first
        setupOptimizedThrottling()
        
        // Optimize audio threads before engine setup
        optimizeAudioThreads()
        
        // Safely setup audio engine
        setupAudioEngine()
        
        // Restore saved pan value if available.
        if let savedPan = UserDefaults.standard.object(forKey: "audioPan") as? Double {
            pan = savedPan
            audioState.lastPanValue = Float(savedPan)
        }
        
        // Setup batch property updates
        setupBatchPropertyUpdates()
        
        // Listen for external notifications to change pan.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handlePanChange),
                                               name: .audioPanChanged,
                                               object: nil)
    }
    
    // MARK: - CPU Optimization Methods
    
    /// Sets up optimized throttling for published properties to minimize CPU usage
    private func setupOptimizedThrottling() {
        // Significantly increase throttling intervals to reduce CPU usage
        
        $isPlaying
            .throttle(for: .milliseconds(2000), scheduler: DispatchQueue.main, latest: true) // Increased from 1000ms
            .removeDuplicates()
            .sink { [weak self] value in 
                self?.batchPropertyUpdate("isPlaying", value: value)
            }
            .store(in: &cancellables)
        
        $duration
            .throttle(for: .milliseconds(5000), scheduler: DispatchQueue.main, latest: true) // Increased from 2000ms
            .removeDuplicates()
            .sink { [weak self] value in 
                self?.batchPropertyUpdate("duration", value: value)
            }
            .store(in: &cancellables)
        
        // Reduce currentTime update frequency significantly for better performance
        $currentTime
            .throttle(for: .milliseconds(1000), scheduler: DispatchQueue.main, latest: true) // Increased from 500ms
            .sink { [weak self] value in 
                self?.batchPropertyUpdate("currentTime", value: value)
            }
            .store(in: &cancellables)
    }
    
    /// Batches property updates to reduce UI refresh frequency
    private func batchPropertyUpdate(_ property: String, value: Any) {
        pendingPropertyUpdates.insert(property)
        
        // Apply the value to cached state immediately
        switch property {
        case "isPlaying":
            if let boolValue = value as? Bool {
                audioState.isPlaying = boolValue
            }
        case "duration":
            if let doubleValue = value as? Double {
                audioState.duration = doubleValue
            }
        case "currentTime":
            if let doubleValue = value as? Double {
                audioState.currentTime = doubleValue
            }
        default:
            break
        }
        
        // Reset timer for batch processing
        propertyUpdateTimer?.invalidate()
        propertyUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.flushPendingPropertyUpdates()
        }
    }
    
    /// Flushes all pending property updates in a single batch
    private func flushPendingPropertyUpdates() {
        guard !pendingPropertyUpdates.isEmpty else { return }
        
        // Update all pending properties in one UI transaction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        for property in pendingPropertyUpdates {
            switch property {
            case "isPlaying":
                isPlaying = audioState.isPlaying
            case "duration":
                duration = audioState.duration
            case "currentTime":
                currentTime = audioState.currentTime
            default:
                break
            }
        }
        
        CATransaction.commit()
        pendingPropertyUpdates.removeAll()
    }
    
    /// Sets up batch property updates system
    private func setupBatchPropertyUpdates() {
        // Initialize the batch update system
        pendingPropertyUpdates.removeAll()
        propertyUpdateTimer?.invalidate()
    }
    
    // MARK: - Optimized Pan AudioProcessingTap
    /// Creates a highly optimized MTAudioProcessingTap that applies pan with minimal CPU overhead.
    /// Returns a tap reference managed via the audio mix. The initial retained reference is consumed.
    private func createPanTap() -> MTAudioProcessingTap? {
        // Define optimized callbacks with minimal processing
        let initCb: MTAudioProcessingTapInitCallback = { (tap, clientInfo, tapStorageOut) in
            guard let ci = clientInfo else { return }
            let player = Unmanaged<AudioPlayer>.fromOpaque(ci).takeUnretainedValue()
            let storage = UnsafeMutablePointer<Float>.allocate(capacity: 1)
            storage.initialize(to: Float(player.pan))
            tapStorageOut.pointee = UnsafeMutableRawPointer(storage)
        }
        let finalizeCb: MTAudioProcessingTapFinalizeCallback = { tap in
            let storageRaw = MTAudioProcessingTapGetStorage(tap)
            storageRaw.assumingMemoryBound(to: Float.self).deallocate()
        }
        let prepareCb: MTAudioProcessingTapPrepareCallback = { _, _, _ in }
        let unprepareCb: MTAudioProcessingTapUnprepareCallback = { _ in }
        let processCb: MTAudioProcessingTapProcessCallback = { (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
            // Highly optimized audio processing with multiple early returns
            let status = MTAudioProcessingTapGetSourceAudio(tap,
                                                            numberFrames,
                                                            bufferListInOut,
                                                            flagsOut,
                                                            nil,
                                                            numberFramesOut)
            guard status == noErr else { return }
            
            // Get pan value with reduced overhead
            let storageRaw = MTAudioProcessingTapGetStorage(tap)
            let panVal: Float = storageRaw.assumingMemoryBound(to: Float.self).pointee
            
            // Multiple early returns to minimize CPU usage
            // 1. Early return if pan is centered (most common case)
            guard abs(panVal - 0.5) > 0.02 else { return } // Increased threshold to reduce processing
            
            // 2. Early return for very small frame counts
            guard numberFrames > 64 else { return }
            
            // 3. Optimized constant power panning calculation
            let clampedPan = max(0.0, min(1.0, panVal))
            
            // Pre-calculate panning coefficients (CPU optimization)
            let panAngle = clampedPan * Float.pi / 2.0
            var leftGain = cos(panAngle)
            var rightGain = sin(panAngle)
            
            // 4. Early return if gains are too similar (no audible difference)
            guard abs(leftGain - rightGain) > 0.05 else { return }

            let abl = UnsafeMutableAudioBufferListPointer(bufferListInOut)
            guard abl.count > 0 else { return }

            // Process only the first buffer for efficiency (most common case)
            if let firstBuffer = abl.first,
               let data = firstBuffer.mData?.assumingMemoryBound(to: Float.self) {
                let chans = Int(firstBuffer.mNumberChannels)
                let frames = Int(numberFrames)
                
                // Optimize for the most common cases first
                if chans == 2 { // Stereo - most common case
                    // Use optimized vectorized operations with stride
                    let frameCount = vDSP_Length(frames)
                    vDSP_vsmul(data, 2, &leftGain, data, 2, frameCount)
                    vDSP_vsmul(data.advanced(by: 1), 2, &rightGain, data.advanced(by: 1), 2, frameCount)
                } else if chans == 1 { // Mono - less common
                    // For mono, use simplified processing
                    var averageGain = sqrt(leftGain * leftGain + rightGain * rightGain)
                    vDSP_vsmul(data, 1, &averageGain, data, 1, vDSP_Length(frames))
                }
                // Skip processing for unusual channel configurations to save CPU
            }
        }
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
                                                     clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                                     init: initCb,
                                                     finalize: finalizeCb,
                                                     prepare: prepareCb,
                                                     unprepare: unprepareCb,
                                                     process: processCb)
        // Create tap
        var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault,
                                              &callbacks,
                                              kMTAudioProcessingTapCreationFlag_PostEffects,
                                              &unmanagedTap)
        guard err == noErr, let uTap = unmanagedTap else {
            print("Failed to create pan tap: \(err)")
            return nil
        }
        // Consume the initial retain, audio mix will hold its own reference
        let tapRef = uTap.takeRetainedValue()
        panTap = tapRef
        return tapRef
    }
    
    /// Configures the audio engine by attaching and connecting the player node.
    /// Also starts the engine and applies initial volume and pan settings.
    private func setupAudioEngine() {
        // Safely attach and connect nodes
        do {
            audioEngine.attach(playerNode)
            
            // Use cached format or create optimized format
            let format = cachedAudioFormat ?? audioEngine.mainMixerNode.outputFormat(forBus: 0)
            if cachedAudioFormat == nil {
                cachedAudioFormat = format
            }
            
            // Configure player node with larger buffer size for efficiency
            playerNode.installTap(onBus: 0, bufferSize: optimizedBufferSize, format: format) { buffer, time in
                // Minimal processing in the tap to reduce CPU overhead
                // Remove any unnecessary processing here
            }
            
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            
            // Apply initial settings in batch
            updateVolumeImmediate()
            updatePanImmediate()
            
            // Configure engine for efficiency
            audioEngine.mainMixerNode.outputVolume = Float(volume)
            
            // Start the engine
            try audioEngine.start()
            engineConfigured = true
            print("Audio engine started successfully with CPU-optimized configuration")
        } catch {
            print("Failed to start audio engine: \(error)")
            // Don't set engineConfigured to true if we failed
        }
    }
    
    /// Updates the pan for the player node (immediate, non-debounced version).
    private func updatePanImmediate() {
        // Validate that pan is finite and within the valid range
        guard pan.isFinite else { 
            print("Warning: Pan value is not finite: \(pan)")
            return 
        }
        
        // CPU Optimization: Skip update if pan hasn't changed significantly
        let panFloat = Float(pan)
        guard abs(audioState.lastPanValue - panFloat) > 0.01 else { return }
        
        // Clamp pan to valid range
        let safePan = max(0, min(1, pan))
        let panValue = Float((safePan * 2) - 1)
        playerNode.pan = panValue
        
        // Update cached state
        audioState.lastPanValue = panFloat
        audioState.rate = playerNode.rate
    }
    
    /// Updates the pan for the player node (debounced version).
    private func updatePan() async {
        updatePanImmediate()
    }
    
    /// Updates the volume for the player node (immediate, non-debounced version).
    private func updateVolumeImmediate() {
        // Validate that volume is finite and within the valid range
        guard volume.isFinite else { return }
        
        // CPU Optimization: Skip update if volume hasn't changed significantly
        let volumeFloat = Float(volume)
        guard abs(audioState.volume - volumeFloat) > 0.01 else { return }
        
        // Clamp volume to valid range
        let safeVolume = max(0, min(1, volume))
        let safeVolumeFloat = Float(safeVolume)
        
        // Batch all volume updates together
        playerNode.volume = safeVolumeFloat
        audioEngine.mainMixerNode.outputVolume = safeVolumeFloat
        player?.volume = safeVolumeFloat
        
        // Update the cached state
        audioState.volume = safeVolumeFloat
    }
    
    /// Updates the volume for the player node (debounced version).
    private func updateVolume() async {
        updateVolumeImmediate()
    }
    
    /// Plays audio from the specified URL.
    /// Cleans up previous playback, sets up a new AVPlayerItem with observers, and starts playback.
    /// - Parameter url: URL of the audio asset (local file or HTTP/HTTPS).
    func playAudio(url: URL) {
        guard url.isFileURL || url.scheme == "http" || url.scheme == "https" else {
            print("Invalid URL: \(url)")
            return
        }
        
        // If we're already playing this URL, just resume playback if paused
        if currentURL == url && player != nil {
            if !isPlaying {
                player?.play()
                playerNode.play()
                DispatchQueue.main.async {
                    self.isPlaying = true
                    self.audioState.isPlaying = true
                }
            }
            return
        }
        
        // Stop existing playback and clean up resources
        stopAudio()
        cleanupObservers()
        
        // Reset playback state immediately on main thread for responsiveness
        DispatchQueue.main.async { 
            self.currentTime = 0
            self.duration = 0
            self.isLoading = true // Indicate loading starts
            self.isPlaying = false
        }
        
        currentURL = url // Update current URL
        
        // Update cached state
        audioState.currentTime = 0
        audioState.duration = 0
        audioState.url = url
        audioState.isPlaying = false
        
        // *** Start Asynchronous Preparation ***
        Task(priority: .userInitiated) { 
            do {
                // Create player item and asset
                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                
                // Load asset duration asynchronously
                let loadedDuration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(loadedDuration)
                let safeDuration = (durationSeconds.isFinite && durationSeconds >= 0) ? durationSeconds : 0
                
                // Setup observers and audio mix for the item
                await setupPlayerItemObservers(playerItem, duration: safeDuration)
                
                // Ensure player is created and configured on the main thread
                await MainActor.run { 
                    // Create a new player with the prepared item
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.volume = Float(self.volume) // Apply current volume
                    self.addOptimizedTimeObserver() // Add optimized time observer
                    
                    // Start playback
                    self.player?.play()
                    if self.engineConfigured { self.playerNode.play() }
                    
                    // Update final state
                    self.isPlaying = true
                    self.isLoading = false
                    self.duration = safeDuration
                    
                    // Update cached state
                    self.audioState.isPlaying = true
                    self.audioState.isLoading = false
                    self.audioState.duration = safeDuration
                }
                
            } catch {
                // Handle errors during async loading
                print("Error preparing audio item: \(error)")
                await MainActor.run { 
                    self.isLoading = false
                    self.isPlaying = false
                    // Potentially show an error state to the user
                }
            }
        }
        // *** End Asynchronous Preparation ***
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
    
    /// Adds a highly optimized periodic time observer to the AVPlayer to update the current playback time.
    /// Optimized to significantly reduce main thread overhead and unnecessary callbacks.
    private func addOptimizedTimeObserver() {
        guard let player = player else { return }
        
        // CPU Optimization: Use much less frequent updates to reduce thread overhead
        // Increase from 0.5s to 1.0s to halve the callback frequency
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
            guard let self = self else { return }
            
            let seconds = time.seconds
            
            // Validate that the time is finite and non-negative
            guard seconds.isFinite && seconds >= 0 else { return }
            
            // CPU Optimization: Use debounced updates to reduce UI refresh frequency
            self.timeUpdateTask?.cancel()
            self.timeUpdateTask = Task { @MainActor [weak self] in 
                guard let self = self else { return }
                
                // Use a larger threshold to reduce unnecessary updates
                let timeDifference = abs(self.currentTime - seconds)
                guard timeDifference > 0.5 else { return } // Increased from 0.25 to 0.5
                
                self.currentTime = seconds
                self.audioState.currentTime = seconds
            }
        }
    }
    
    /// Removes the periodic time observer and invalidates the duration observer.
    @MainActor
    private func cleanupObservers() {
        if let player = player, let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        durationObserver?.invalidate()
        durationObserver = nil
        // Remove the audio mix from the current item to tear down taps and release MediaToolbox resources
        if let item = player?.currentItem {
            item.audioMix = nil
            // Remove reference to the item so it can deallocate
            player?.replaceCurrentItem(with: nil)
        }
        
        // Cancel any pending update tasks
        timeUpdateTask?.cancel()
        volumeUpdateTask?.cancel()
        panUpdateTask?.cancel()
    }
    
    /// Handles external notifications to update the pan setting.
    /// - Parameter notification: Notification containing a new pan value.
    @objc private func handlePanChange(_ notification: Notification) {
        if let panValue = notification.userInfo?["pan"] as? Double {
            print("🎧 Received pan change notification: \(panValue)")
            
            // Validate that the pan value is finite and within the valid range
            guard panValue.isFinite else {
                print("Warning: Received invalid pan value: \(panValue)")
                return
            }
            
            // Clamp pan to valid range
            let safePan = max(0, min(1, panValue))
            pan = safePan
            
            // Update the AVAudioPlayerNode pan (for local files)
            updatePanImmediate()
            
            // Update storage for existing audio tap so streaming pan updates work
            if let tapRef = panTap {
                let storageRaw = MTAudioProcessingTapGetStorage(tapRef)
                storageRaw.assumingMemoryBound(to: Float.self).pointee = Float(safePan)
                print("🎧 Updated audio tap storage with pan value: \(safePan)")
            } else {
                print("🎧 No audio tap available for pan update")
            }
            
            print("🎧 Pan change complete: \(safePan)")
        } else {
            print("Warning: Pan change notification missing or invalid pan value")
        }
    }
    
    /// Cleans up resources on deinitialization.
    /// Removes observers, stops playback, and resets the audio engine.
    deinit {
        // Cancel all pending tasks
        timeUpdateTask?.cancel()
        volumeUpdateTask?.cancel()
        panUpdateTask?.cancel()
        
        // Invalidate timers
        propertyUpdateTimer?.invalidate()
        
        // Perform synchronous cleanup that is safe from deinit
        NotificationCenter.default.removeObserver(self)
        // player?.pause() // Avoid potentially unsafe calls from deinit
        // playerNode.stop()
        // audioEngine.stop()
        // cleanupObservers() cannot be safely called from here
        // Rely on ARC and Combine to clean up remaining resources
    }
    
    /// Sets up an observer on the AVPlayerItem to monitor its status.
    /// Updates the audio duration when the item is ready to play.
    /// - Parameter playerItem: The AVPlayerItem to observe.
    /// - Parameter duration: The pre-loaded duration (optional)
    private func setupPlayerItemObservers(_ playerItem: AVPlayerItem, duration: Double?) async {
        // Note: panning via AVPlayerItem.audioMix is not supported; audioEngine pan applies only to local playback
        // Prepare params list in background
        var paramsListInBackground: [AVAudioMixInputParameters] = []
        
        do {
            // Load tracks asynchronously
            let tracks = try await playerItem.asset.load(.tracks)
            for track in tracks where track.mediaType == .audio {
                let params = AVMutableAudioMixInputParameters(track: track)
                // Install a tap for pan control on the audio track
                if let tapRef = createPanTap() {
                    params.audioTapProcessor = tapRef
                }
                paramsListInBackground.append(params)
            }
        } catch {
            print("Error loading tracks for audio mix: \(error)")
        }
        
        // Create and assign mix on the main actor
        await MainActor.run { 
            let mix = AVMutableAudioMix()
            mix.inputParameters = paramsListInBackground
            playerItem.audioMix = mix
        }
        
        // Observe status for potential errors or buffering states
        durationObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, change in
            guard let self = self else { return }
            Task { @MainActor in // Ensure UI updates are on main thread
                switch item.status {
                case .readyToPlay:
                    // If duration wasn't pre-loaded or differs, update it
                    let currentDuration = item.duration.seconds
                    if self.duration != currentDuration && currentDuration.isFinite && currentDuration >= 0 {
                        self.duration = currentDuration
                        self.audioState.duration = currentDuration
                    }
                    self.isLoading = false // Ready, no longer loading
                case .failed:
                    print("Error: AVPlayerItem failed: \(item.error?.localizedDescription ?? "Unknown error")")
                    self.isLoading = false
                    self.isPlaying = false
                    // Maybe reset player or show error
                case .unknown:
                    self.isLoading = true // Still loading or unknown state
                @unknown default:
                    self.isLoading = true
                }
            }
        }
        
        // Optionally observe other properties like playbackBufferEmpty, playbackLikelyToKeepUp
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
    
    // MARK: - Thread Optimization Methods
    
    /// Optimizes audio processing to reduce thread overhead and improve performance
    /// This addresses the multiple audio threads shown in the profiler
    private func optimizeAudioThreads() {
        // Configure audio engine for optimal performance on macOS
        if engineConfigured {
            // Remove unnecessary taps that create additional processing threads
            playerNode.removeTap(onBus: 0)
            
            // Configure engine with minimal processing
            audioEngine.mainMixerNode.outputVolume = Float(volume)
            
            // Set optimal buffer size for macOS
            if let format = cachedAudioFormat {
                // Reinstall tap with optimized settings and larger buffer
                playerNode.installTap(onBus: 0, bufferSize: optimizedBufferSize, format: format) { buffer, time in
                    // Minimal processing to reduce overhead
                    // Remove any debugging or unnecessary operations here
                }
            }
            
            // Reset engine with optimized settings if needed
            if !audioEngine.isRunning {
                do {
                    try audioEngine.start()
                } catch {
                    print("Failed to restart optimized audio engine: \(error)")
                }
            }
        }
    }
    
    /// Consolidates audio operations to reduce system overhead
    private func consolidateAudioOperations() {
        // Batch multiple audio property changes together
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Apply all audio changes in one transaction
        if let player = player {
            player.volume = Float(volume)
            if engineConfigured {
                playerNode.volume = Float(volume)
                playerNode.pan = Float((pan * 2) - 1)
                audioEngine.mainMixerNode.outputVolume = Float(volume)
            }
        }
        
        CATransaction.commit()
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let audioPanChanged = Notification.Name("audioPanChanged")
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
