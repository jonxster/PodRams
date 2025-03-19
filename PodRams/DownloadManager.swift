//
// DownloadManager.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import CryptoKit
import os.log

/// Manages downloading of podcast episodes.
/// This singleton class uses URLSession to download episodes and tracks their download states.
/// It handles creating required directories, monitoring download progress, and moving downloaded files.
class DownloadManager: ObservableObject, @unchecked Sendable {
    /// Shared singleton instance for global access.
    static let shared = DownloadManager()
    
    /// Enum representing the various states of a download.
    enum DownloadState: Equatable {
        case none
        case downloading(progress: Double)
        case downloaded(URL)
        case failed(Error)
        
        /// Custom equality implementation to compare download states.
        static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case let (.downloading(p1), .downloading(p2)):
                return p1 == p2
            case let (.downloaded(url1), .downloaded(url2)):
                return url1 == url2
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }
    
    /// Published dictionary that maps each episode's URL (as a string) to its current download state.
    @Published var downloadStates: [String: DownloadState] = [:]
    /// Dictionary holding active download tasks, keyed by episode URL string.
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    /// Dictionary holding progress observations for each download task.
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    /// File manager used for file operations.
    private let fileManager = FileManager.default
    
    /// Logger for download operations
    private let logger = Logger(subsystem: "com.podrams", category: "DownloadManager")
    
    /// Dedicated queue for file operations
    private let fileOperationQueue = DispatchQueue(label: "com.podrams.fileOperations", 
                                                  qos: .utility, 
                                                  attributes: .concurrent)
    
    /// Cache for file existence checks to reduce disk I/O
    private var fileExistenceCache: [String: (exists: Bool, timestamp: Date)] = [:]
    private let cacheValidityDuration: TimeInterval = 5.0 // Cache valid for 5 seconds
    
    /// Custom URLSession for downloads
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Optimize for large file downloads
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForResource = 60 * 60 // 1 hour timeout for large files
        config.waitsForConnectivity = true
        
        // Use a larger memory capacity for better performance on Apple Silicon
        config.urlCache = URLCache(memoryCapacity: 50_000_000, // 50MB memory cache
                                  diskCapacity: 1_000_000_000, // 1GB disk cache
                                  directory: nil)
        
        return URLSession(configuration: config)
    }()
    
    /// Private initializer to enforce singleton pattern.
    private init() {
        // Ensure required directories are available on initialization.
        createRequiredDirectories()
        
        // Load saved download states
        Task {
            await loadDownloadStates()
        }
    }
    
    /// Creates necessary directories (Downloads and tmp) inside the user's document directory.
    private func createRequiredDirectories() {
        // Use the file operation queue for disk operations
        fileOperationQueue.async {
            let fileManager = FileManager.default
            // Obtain the user's document directory.
            let containerURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let downloadsURL = containerURL.appendingPathComponent("Downloads")
            let tmpURL = containerURL.appendingPathComponent("tmp")
            
            do {
                // Create the Downloads directory if it doesn't exist.
                if !fileManager.fileExists(atPath: downloadsURL.path) {
                    try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
                    self.logger.info("Created Downloads directory at: \(downloadsURL.path)")
                }
                
                // Create the temporary directory if it doesn't exist.
                if !fileManager.fileExists(atPath: tmpURL.path) {
                    try fileManager.createDirectory(at: tmpURL, withIntermediateDirectories: true)
                    self.logger.info("Created tmp directory at: \(tmpURL.path)")
                }
            } catch {
                self.logger.error("Error creating directories: \(error.localizedDescription)")
            }
        }
    }
    
    /// Computes the SHA256 hash for a given string.
    /// - Parameter string: The input string (typically a URL's absolute string).
    /// - Returns: A hexadecimal representation of the SHA256 hash, used to generate a unique filename.
    private func sha256(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Returns the local file URL where a downloaded episode should be stored.
    /// Ensures that the Downloads directory exists.
    /// - Parameter episode: The podcast episode to be downloaded.
    /// - Returns: The destination URL for the downloaded file.
    private func localFileURL(for episode: PodcastEpisode) -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        
        // Ensure the Downloads directory exists.
        if !fileManager.fileExists(atPath: downloadsDir.path) {
            do {
                try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
                logger.info("Created Downloads directory at: \(downloadsDir.path)")
            } catch {
                logger.error("Error creating Downloads directory: \(error.localizedDescription)")
            }
        }
        
        // Use SHA256 of the episode URL to generate a unique filename.
        let urlString = episode.url.absoluteString
        let hash = sha256(urlString)
        let ext = episode.url.pathExtension
        let fileName = hash + (ext.isEmpty ? "" : ".\(ext)")
        return downloadsDir.appendingPathComponent(fileName)
    }
    
    /// Loads saved download states from persistence
    private func loadDownloadStates() async {
        let savedDownloads = await PersistenceManager.loadDownloads()
        
        // Process downloads in batches for better cache utilization
        let batchSize = 20
        for i in stride(from: 0, to: savedDownloads.count, by: batchSize) {
            let endIndex = min(i + batchSize, savedDownloads.count)
            let batch = Array(savedDownloads[i..<endIndex])
            
            // Process each batch concurrently
            await withTaskGroup(of: (String, URL?).self) { group in
                for download in batch {
                    group.addTask {
                        let fileURL = URL(fileURLWithPath: download.localFilePath)
                        
                        // Check file existence on a background thread
                        let exists = FileManager.default.fileExists(atPath: fileURL.path)
                        return (download.episodeUrl, exists ? fileURL : nil)
                    }
                }
                
                // Collect results and update states
                var updates = [(String, URL)]()
                for await (episodeUrl, fileURL) in group {
                    if let url = fileURL {
                        updates.append((episodeUrl, url))
                    }
                }
                
                // Update states on main thread in a single batch
                let finalUpdates = updates // Create a local copy to avoid capture issues
                if !finalUpdates.isEmpty {
                    await MainActor.run {
                        for (episodeUrl, url) in finalUpdates {
                            self.downloadStates[episodeUrl] = .downloaded(url)
                        }
                    }
                }
            }
        }
    }
    
    /// Saves the current download states to persistence
    private func saveDownloadStates() {
        // Use the file operation queue for disk operations
        fileOperationQueue.async {
            var downloads: [PersistedDownload] = []
            
            for (episodeUrl, state) in self.downloadStates {
                if case let .downloaded(url) = state {
                    downloads.append(PersistedDownload(
                        episodeUrl: episodeUrl,
                        localFilePath: url.path
                    ))
                }
            }
            
            PersistenceManager.saveDownloads(downloads)
        }
    }
    
    /// Posts a notification that a download has been completed
    private func postDownloadCompletedNotification(for episode: PodcastEpisode) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("DownloadCompleted"),
                object: nil,
                userInfo: ["episodeUrl": episode.url.absoluteString]
            )
            print("DownloadManager: Posted DownloadCompleted notification for \(episode.title)")
        }
    }
    
    /// Starts downloading a podcast episode.
    /// Sets up progress observation and moves the downloaded file to the Downloads directory upon completion.
    /// - Parameter episode: The podcast episode to download.
    func downloadEpisode(_ episode: PodcastEpisode) {
        // Ensure required directories are created before beginning the download.
        createRequiredDirectories()
        
        let key = episode.url.absoluteString
        // If a download is already in progress or completed, do nothing.
        guard downloadStates[key] == nil else {
            logger.info("Episode is already being downloaded or has been downloaded: \(episode.title)")
            print("DownloadManager: Episode is already being downloaded or has been downloaded: \(episode.title)")
            return
        }
        
        logger.info("Starting download for episode: \(episode.title)")
        print("DownloadManager: Starting download for episode: \(episode.title)")
        
        // Set the initial state to downloading with 0 progress
        downloadStates[key] = .downloading(progress: 0.0)
        print("DownloadManager: Set initial state to downloading for \(episode.title)")
        
        // Create a download task for the episode using the optimized session
        let task = downloadSession.downloadTask(with: episode.url) { [weak self] tempURL, response, error in
            guard let downloadManager = self else { return }
            
            // Handle error scenario.
            if let error = error {
                downloadManager.logger.error("Download error for episode '\(episode.title)': \(error.localizedDescription)")
                print("DownloadManager: Download error for episode '\(episode.title)': \(error.localizedDescription)")
                DispatchQueue.main.async {
                    downloadManager.downloadStates[key] = .failed(error)
                    downloadManager.saveDownloadStates()
                }
                return
            }
            
            // Ensure a temporary URL is provided.
            guard let tempURL = tempURL else {
                downloadManager.logger.error("No temporary URL provided for downloaded file: \(episode.title)")
                DispatchQueue.main.async {
                    downloadManager.downloadStates[key] = .failed(NSError(domain: "DownloadManager", code: -1))
                    downloadManager.saveDownloadStates()
                }
                return
            }
            
            // Use the file operation queue for file operations
            downloadManager.fileOperationQueue.async {
                let fileManager = FileManager.default
                let containerURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let downloadsURL = containerURL.appendingPathComponent("Downloads")
                
                // Generate destination filename using SHA256 hash with a ".mp3" extension.
                let filename = downloadManager.sha256(episode.url.absoluteString) + ".mp3"
                let destinationURL = downloadsURL.appendingPathComponent(filename)
                
                do {
                    // Remove any existing file at the destination.
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    
                    // Move the downloaded file from the temporary location to the final destination.
                    try fileManager.moveItem(at: tempURL, to: destinationURL)
                    downloadManager.logger.info("Successfully moved downloaded file to: \(destinationURL.path)")
                    
                    // Update the file existence cache
                    downloadManager.updateFileExistenceCache(path: destinationURL.path, exists: true)
                    
                    DispatchQueue.main.async {
                        downloadManager.downloadStates[key] = .downloaded(destinationURL)
                        downloadManager.saveDownloadStates()
                        downloadManager.postDownloadCompletedNotification(for: episode)
                    }
                } catch {
                    downloadManager.logger.error("Error moving file for episode '\(episode.title)': \(error.localizedDescription)")
                    
                    // Fallback: Try copying the file instead of moving.
                    do {
                        try fileManager.copyItem(at: tempURL, to: destinationURL)
                        downloadManager.logger.info("Successfully copied file using fallback method")
                        
                        // Update the file existence cache
                        downloadManager.updateFileExistenceCache(path: destinationURL.path, exists: true)
                        
                        DispatchQueue.main.async {
                            downloadManager.downloadStates[key] = .downloaded(destinationURL)
                            downloadManager.saveDownloadStates()
                            downloadManager.postDownloadCompletedNotification(for: episode)
                        }
                    } catch {
                        downloadManager.logger.error("Fallback copy also failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            downloadManager.downloadStates[key] = .failed(error)
                            downloadManager.saveDownloadStates()
                        }
                    }
                }
            }
        }
        
        // Observe download progress and update the download state accordingly.
        progressObservations[key] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let downloadManager = self else { return }
            
            // Throttle UI updates for better performance
            // Only update UI when progress changes by at least 1%
            let newProgress = progress.fractionCompleted
            if case let .downloading(oldProgress) = downloadManager.downloadStates[key],
               abs(newProgress - oldProgress) < 0.01 && oldProgress > 0 && newProgress < 1.0 {
                return
            }
            
            print("DownloadManager: Progress update for \(episode.title): \(newProgress)")
            
            DispatchQueue.main.async {
                downloadManager.downloadStates[key] = .downloading(progress: newProgress)
            }
        }
        
        downloadTasks[key] = task
        task.resume()
        print("DownloadManager: Download task started for \(episode.title)")
    }
    
    /// Removes a downloaded episode from local storage and updates its download state.
    /// Also cleans up any associated progress observations.
    /// - Parameter episode: The podcast episode to remove.
    func removeDownload(for episode: PodcastEpisode) {
        let key = episode.url.absoluteString
        // Invalidate and remove the progress observation.
        progressObservations[key]?.invalidate()
        progressObservations[key] = nil
        
        let destinationURL = localFileURL(for: episode)
        
        // Use the file operation queue for file operations
        fileOperationQueue.async {
            do {
                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    try self.fileManager.removeItem(at: destinationURL)
                    self.logger.info("Removed downloaded file for episode '\(episode.title)' at: \(destinationURL.path)")
                    
                    // Update the file existence cache
                    self.updateFileExistenceCache(path: destinationURL.path, exists: false)
                }
                
                // Explicitly set the state to .none after removal.
                // Use explicit type to avoid ambiguity with Optional.none
                DispatchQueue.main.async {
                    self.downloadStates[key] = DownloadState.none
                    self.saveDownloadStates()
                }
            } catch {
                self.logger.error("Error removing downloaded episode '\(episode.title)': \(error.localizedDescription)")
            }
        }
    }
    
    /// Returns the local file URL for a downloaded episode, if it exists.
    /// - Parameter episode: The podcast episode to check.
    /// - Returns: The local URL if the episode is downloaded; otherwise, nil.
    func localURL(for episode: PodcastEpisode) -> URL? {
        let key = episode.url.absoluteString
        
        // First check if we have the download state in memory
        if case let .downloaded(url) = downloadStates[key] {
            // Check the file existence cache first
            if let (exists, _) = checkFileExistenceCache(path: url.path) {
                return exists ? url : nil
            }
            
            // If not in cache, check the file system
            if FileManager.default.fileExists(atPath: url.path) {
                // Update the cache
                updateFileExistenceCache(path: url.path, exists: true)
                return url
            } else {
                // File doesn't exist anymore, update state and cache
                updateFileExistenceCache(path: url.path, exists: false)
                DispatchQueue.main.async {
                    self.downloadStates[key] = DownloadState.none
                    self.saveDownloadStates()
                }
                return nil
            }
        }
        
        // If not in memory, check if the file exists on disk
        let potentialURL = localFileURL(for: episode)
        
        // Check the cache first
        if let (exists, _) = checkFileExistenceCache(path: potentialURL.path) {
            if exists {
                DispatchQueue.main.async {
                    self.downloadStates[key] = .downloaded(potentialURL)
                    self.saveDownloadStates()
                }
                return potentialURL
            }
            return nil
        }
        
        // If not in cache, check the file system
        if FileManager.default.fileExists(atPath: potentialURL.path) {
            // Update the cache
            updateFileExistenceCache(path: potentialURL.path, exists: true)
            
            // File exists, update the state and return the URL
            DispatchQueue.main.async {
                self.downloadStates[key] = .downloaded(potentialURL)
                self.saveDownloadStates()
            }
            return potentialURL
        } else {
            // Update the cache
            updateFileExistenceCache(path: potentialURL.path, exists: false)
        }
        
        return nil
    }
    
    /// Checks if an episode is downloaded without changing its state.
    /// - Parameter episode: The podcast episode to check.
    /// - Returns: True if the episode is downloaded; otherwise, false.
    func isDownloaded(_ episode: PodcastEpisode) -> Bool {
        let key = episode.url.absoluteString
        
        // First check if we have the download state in memory
        if case let .downloaded(url) = downloadStates[key] {
            // Check the cache first
            if let (exists, _) = checkFileExistenceCache(path: url.path) {
                return exists
            }
            
            // If not in cache, check the file system
            let exists = FileManager.default.fileExists(atPath: url.path)
            updateFileExistenceCache(path: url.path, exists: exists)
            return exists
        }
        
        // If not in memory, check if the file exists on disk
        let potentialURL = localFileURL(for: episode)
        
        // Check the cache first
        if let (exists, _) = checkFileExistenceCache(path: potentialURL.path) {
            return exists
        }
        
        // If not in cache, check the file system
        let exists = FileManager.default.fileExists(atPath: potentialURL.path)
        updateFileExistenceCache(path: potentialURL.path, exists: exists)
        return exists
    }
    
    /// Checks the file existence cache for a given path
    /// - Parameter path: The file path to check
    /// - Returns: A tuple containing whether the file exists and the timestamp of the cache entry, or nil if not in cache
    private func checkFileExistenceCache(path: String) -> (exists: Bool, timestamp: Date)? {
        guard let cacheEntry = fileExistenceCache[path] else {
            return nil
        }
        
        // Check if the cache entry is still valid
        if Date().timeIntervalSince(cacheEntry.timestamp) > cacheValidityDuration {
            return nil
        }
        
        return cacheEntry
    }
    
    /// Updates the file existence cache for a given path
    /// - Parameters:
    ///   - path: The file path to update
    ///   - exists: Whether the file exists
    private func updateFileExistenceCache(path: String, exists: Bool) {
        fileExistenceCache[path] = (exists: exists, timestamp: Date())
        
        // Periodically clean up the cache
        if fileExistenceCache.count > 1000 {
            cleanupFileExistenceCache()
        }
    }
    
    /// Cleans up expired entries from the file existence cache
    private func cleanupFileExistenceCache() {
        let now = Date()
        let keysToRemove = fileExistenceCache.filter { 
            now.timeIntervalSince($0.value.timestamp) > cacheValidityDuration
        }.keys
        
        for key in keysToRemove {
            fileExistenceCache.removeValue(forKey: key)
        }
    }
    
    /// Gets the current download state for an episode
    /// - Parameter episode: The podcast episode to check
    /// - Returns: The current download state
    func downloadState(for episode: PodcastEpisode) -> DownloadState {
        let key = episode.url.absoluteString
        
        // First check if we have a state in memory
        if let state = downloadStates[key] {
            // For downloaded state, verify the file still exists
            if case let .downloaded(url) = state {
                if FileManager.default.fileExists(atPath: url.path) {
                    return state
                } else {
                    // File no longer exists, update state
                    DispatchQueue.main.async {
                        self.downloadStates[key] = DownloadState.none
                        self.saveDownloadStates()
                    }
                    return DownloadState.none
                }
            }
            return state
        }
        
        // If not in memory, check if the file exists on disk
        if let url = localURL(for: episode) {
            return .downloaded(url)
        }
        
        return DownloadState.none
    }
    
    deinit {
        // Clean up all progress observations when the DownloadManager is deallocated.
        progressObservations.values.forEach { $0.invalidate() }
        progressObservations.removeAll()
    }
}
