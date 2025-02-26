//
//  AudioPlayer.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import AVFoundation

class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.5 {
        didSet { updateVolume() }
    }
    // Pan is stored as 0 (full left) to 1 (full right), 0.5 is center.
    @Published var pan: Double = 0.5 {
        didSet {
            updatePan()
            UserDefaults.standard.set(pan, forKey: "audioPan")
        }
    }
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var durationObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    private var currentURL: URL?
    private var engineConfigured = false
    
    init() {
        setupThrottling()
        setupAudioEngine()
        
        if let savedPan = UserDefaults.standard.object(forKey: "audioPan") as? Double {
            pan = savedPan
        }
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handlePanChange),
                                               name: .audioPanChanged,
                                               object: nil)
    }
    
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
    
    private func updatePan() {
        // Convert pan from 0...1 (with 0.5 as center) to -1...1.
        let panValue = Float((pan * 2) - 1)
        playerNode.pan = panValue
        print("Player node pan set to: \(panValue)")
    }
    
    private func updateVolume() {
        playerNode.volume = Float(volume)
        audioEngine.mainMixerNode.outputVolume = Float(volume)
        player?.volume = Float(volume)
        print("Volume set to: \(volume)")
    }
    
    func playAudio(url: URL) {
        guard url.isFileURL || url.scheme == "http" || url.scheme == "https" else {
            print("Invalid URL: \(url)")
            return
        }
        
        print("Playing audio from URL: \(url)")
        
        // Clean up existing playback
        stopAudio()
        cleanupObservers()
        
        // Reset state
        isPlaying = false
        currentTime = 0
        duration = 0
        isLoading = true
        currentURL = url
        
        // Create new player
        let playerItem = AVPlayerItem(url: url)
        setupPlayerItem(playerItem)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        
        // Always use AVPlayer for both remote and local files
        player?.volume = Float(volume)
        addPeriodicTimeObserver()
        player?.play()
        isPlaying = true
        isLoading = false
    }
    
    private func playThroughAudioEngine(url: URL) {
        // Temporarily disable audio engine playback and use AVPlayer for all files
        player?.volume = Float(volume)
        player?.play()
        isPlaying = true
    }
    
    func pauseAudio() {
        player?.pause()
        playerNode.pause()
        isPlaying = false
    }
    
    func stopAudio() {
        player?.pause()
        player?.seek(to: .zero)
        playerNode.stop()
        isPlaying = false
    }
    
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
    
    func preloadAudio(url: URL) {
        print("Preloading asset for \(url)")
        if url.isFileURL { _ = try? AVAudioFile(forReading: url) }
    }
    
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
    
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    private func cleanupObservers() {
        if let player = player, let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        durationObserver?.invalidate()
        durationObserver = nil
    }
    
    @objc private func handlePanChange(_ notification: Notification) {
        if let panValue = notification.userInfo?["pan"] as? Double {
            pan = panValue
        }
    }
    
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
