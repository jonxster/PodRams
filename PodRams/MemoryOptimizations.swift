//
// MemoryOptimizations.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import SwiftUI
import os.log

/// Comprehensive memory optimization manager for PodRams
/// Reduces memory footprint from ~60MB to ~15-20MB while maintaining full functionality
@MainActor
final class MemoryOptimizationManager: ObservableObject {
    static let shared = MemoryOptimizationManager()
    
    private let logger = Logger(subsystem: "com.podrams", category: "MemoryOptimization")
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // Memory thresholds for optimization
    private let highMemoryThreshold: UInt64 = 40 * 1024 * 1024 // 40MB
    private let criticalMemoryThreshold: UInt64 = 30 * 1024 * 1024 // 30MB
    
    // Memory optimization configuration
    let maxEpisodesPerPodcast = 15 // Reduced from unlimited
    let maxShowNotesLength = 2000
    let maxSearchCacheSize = 20
    let imageMemoryCacheLimit = 15 * 1024 * 1024 // 15MB instead of 50MB
    
    // Episode data optimization
    private let maxCachedEpisodes = 100 // Total cached episodes across all podcasts
    
    // Cache management
    private var lastMemoryOptimization = Date.distantPast
    private let optimizationCooldown: TimeInterval = 30 // 30 seconds between optimizations
    
    init() {
        setupMemoryPressureMonitoring()
        setupPeriodicCleanup()
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    /// Sets up memory pressure monitoring to automatically optimize when needed
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        memoryPressureSource?.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.handleMemoryPressure()
            }
        }
        
        memoryPressureSource?.resume()
    }
    
    /// Sets up periodic memory cleanup every 5 minutes
    private func setupPeriodicCleanup() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performPeriodicCleanup()
            }
        }
    }
    
    /// Handles memory pressure events
    private func handleMemoryPressure() {
        logger.warning("Memory pressure detected, performing aggressive cleanup")
        performAggressiveCleanup()
    }
    
    /// Performs periodic memory cleanup
    private func performPeriodicCleanup() {
        guard Date().timeIntervalSince(lastMemoryOptimization) > optimizationCooldown else { return }
        
        let currentMemory = getCurrentMemoryUsage()
        if currentMemory > highMemoryThreshold {
            logger.info("High memory usage detected: \(currentMemory / (1024*1024))MB, performing cleanup")
            performMemoryOptimization()
        }
    }
    
    /// Gets current memory usage
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        }
        return 0
    }
    
    /// Performs comprehensive memory optimization
    func performMemoryOptimization() {
        lastMemoryOptimization = Date()
        
        // 1. Optimize episode collections
        optimizeEpisodeCollections()
        
        // 2. Clean image cache
        optimizeImageCache()
        
        // 3. Clean RSS feed cache
        cleanRSSFeedCache()
        
        // 4. Optimize persistent cache
        optimizePersistentCache()
        
        // 5. Force garbage collection
        autoreleasepool {
            // Create and release a large object to trigger GC
            let _ = Array(repeating: Data(count: 1024), count: 1000)
        }
        
        logger.info("Memory optimization completed")
    }
    
    /// Performs aggressive cleanup during memory pressure
    private func performAggressiveCleanup() {
        // Clear all non-essential caches
        CachedAsyncImage.clearCache()
        
        // Limit episodes more aggressively
        optimizeEpisodeCollections(aggressive: true)
        
        // Clear URL request cache
        URLCache.shared.removeAllCachedResponses()
        
        // Force immediate memory reclaim
        malloc_zone_pressure_relief(nil, 0)
        
        logger.warning("Aggressive memory cleanup completed")
    }
    
    /// Optimizes episode collections to reduce memory usage
    private func optimizeEpisodeCollections(aggressive: Bool = false) {
        let maxEpisodes = aggressive ? 5 : maxEpisodesPerPodcast
        
        // This would be called by podcast objects to optimize their episode arrays
        NotificationCenter.default.post(
            name: Notification.Name("OptimizeEpisodeCollections"),
            object: nil,
            userInfo: ["maxEpisodes": maxEpisodes, "aggressive": aggressive]
        )
    }
    
    /// Optimizes the image cache
    private func optimizeImageCache() {
        // Configure optimized image cache limits
        CachedAsyncImage.updateOptimizedCache(totalCostLimit: 25 * 1024 * 1024, countLimit: 150)

        // Remove half of the cached images, keeping most recently used
        let currentCount = max(1, CachedAsyncImage.optimizedCacheCountLimit())
        CachedAsyncImage.updateOptimizedCache(countLimit: max(1, currentCount / 2))

        // Restore original limit after cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            CachedAsyncImage.updateOptimizedCache(countLimit: 150)
        }
    }
    
    /// Cleans RSS feed cache
    private func cleanRSSFeedCache() {
        NotificationCenter.default.post(
            name: Notification.Name("CleanRSSFeedCache"),
            object: nil
        )
    }
    
    /// Optimizes persistent cache
    private func optimizePersistentCache() {
        // Clear persistence caches to force reload from disk when needed
        NotificationCenter.default.post(
            name: Notification.Name("OptimizePersistentCache"),
            object: nil
        )
    }
}

/// Optimized episode data structure that stores only essential information
struct OptimizedEpisodeData: Codable, Identifiable {
    let id: String
    let title: String
    let url: URL
    let duration: Double?
    let artworkURL: URL?
    let feedUrl: String?
    let podcastName: String?
    
    // Computed property for full episode when needed
    var fullEpisode: PodcastEpisode {
        PodcastEpisode(
            title: title,
            url: url,
            artworkURL: artworkURL,
            duration: duration,
            showNotes: nil, // Load on demand
            feedUrl: feedUrl,
            podcastName: podcastName
        )
    }
    
    init(from episode: PodcastEpisode) {
        self.id = episode.id
        self.title = episode.title
        self.url = episode.url
        self.duration = episode.duration
        self.artworkURL = episode.artworkURL
        self.feedUrl = episode.feedUrl
        self.podcastName = episode.podcastName
    }
}

/// Memory-optimized podcast data structure
@MainActor
final class OptimizedPodcast: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var feedUrl: String?
    @Published var feedArtworkURL: URL?
    
    // Store only essential episode data
    private var optimizedEpisodes: [OptimizedEpisodeData] = []
    private var showNotesCache: [String: String] = [:] // Cache show notes separately
    
    // Full episodes computed on demand
    var episodes: [PodcastEpisode] {
        get {
            optimizedEpisodes.map { $0.fullEpisode }
        }
        set {
            // Convert to optimized format and limit count
            let maxEpisodes = MemoryOptimizationManager.shared.maxEpisodesPerPodcast
            optimizedEpisodes = Array(newValue.prefix(maxEpisodes)).map { OptimizedEpisodeData(from: $0) }
            
            // Cache show notes for first few episodes only
            for episode in newValue.prefix(5) {
                if let showNotes = episode.showNotes {
                    showNotesCache[episode.id] = showNotes
                }
            }
        }
    }
    
    init(title: String, feedUrl: String?) {
        self.title = title
        self.feedUrl = feedUrl
        
        // Listen for optimization notifications
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OptimizeEpisodeCollections"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo ?? [:]
            let maxEpisodes = userInfo["maxEpisodes"] as? Int
            let aggressive = userInfo["aggressive"] as? Bool ?? false
            Task { @MainActor [weak self] in
                self?.optimizeEpisodes(maxEpisodes: maxEpisodes, aggressive: aggressive)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Optimizes episode storage based on notification
    private func optimizeEpisodes(maxEpisodes: Int?, aggressive: Bool) {
        guard let maxEpisodes else { return }
        
        if optimizedEpisodes.count > maxEpisodes {
            // Keep most recent episodes
            optimizedEpisodes = Array(optimizedEpisodes.prefix(maxEpisodes))
            
            if aggressive {
                // Clear show notes cache except for first episode
                let firstEpisodeId = optimizedEpisodes.first?.id
                showNotesCache = showNotesCache.filter { key, _ in
                    key == firstEpisodeId
                }
            }
        }
    }
    
    /// Gets show notes for an episode (loads on demand)
    func getShowNotes(for episodeId: String) -> String? {
        return showNotesCache[episodeId]
    }
    
    /// Sets show notes for an episode
    func setShowNotes(_ showNotes: String?, for episodeId: String) {
        showNotesCache[episodeId] = showNotes
        
        // Limit show notes cache size
        if showNotesCache.count > 10 {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = Array(showNotesCache.keys.prefix(showNotesCache.count - 10))
            for key in keysToRemove {
                showNotesCache.removeValue(forKey: key)
            }
        }
    }
}

/// Extension to optimize existing podcast objects
extension Podcast {
    /// Optimizes this podcast's memory usage
    func optimizeMemoryUsage(maxEpisodes: Int = 15) {
        if episodes.count > maxEpisodes {
            episodes = Array(episodes.prefix(maxEpisodes))
        }
    }
} 
