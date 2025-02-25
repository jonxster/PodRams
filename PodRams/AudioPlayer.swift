//
//  AudioPlayer.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// AudioPlayer.swift

import Foundation
import Combine
import AVFoundation

class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.5 {
        didSet { player?.volume = Float(volume) }
    }
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var durationObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupThrottling()
    }
    
    func playAudio(url: URL) {
        guard url.isFileURL || url.scheme == "http" || url.scheme == "https" else {
            print("Invalid URL: \(url)")
            return
        }
        
        // If this URL is already loaded, resume playback.
        if let currentPlayer = player,
           let currentItem = currentPlayer.currentItem,
           let assetURL = (currentItem.asset as? AVURLAsset)?.url,
           assetURL == url {
            currentPlayer.play()
            isPlaying = true
            return
        }
        
        cleanupObservers()
        isLoading = true
        
        let playerItem = AVPlayerItem(url: url)
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
        
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.volume = Float(volume)
        player = newPlayer
        
        addPeriodicTimeObserver()
        newPlayer.play()
        isPlaying = true
    }
    
    func pauseAudio() {
        player?.pause()
        isPlaying = false
    }
    
    func stopAudio() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }
    
    /// Preloads media data concurrently using AVAsset’s async API.
    func preloadAudio(url: URL) {
        let asset = AVURLAsset(url: url)
        Task {
            do {
                async let loadedDuration: CMTime = asset.load(.duration)
                async let loadedTracks: [AVAssetTrack] = asset.load(.tracks)
                let durationValue = try await loadedDuration
                _ = try await loadedTracks
                print("Preloaded asset for \(url), duration: \(CMTimeGetSeconds(durationValue)) seconds")
            } catch {
                print("Preload failed for \(url): \(error)")
            }
        }
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
    
    deinit {
        cleanupObservers()
        player?.pause()
        player = nil
        cancellables.removeAll()
    }
}
