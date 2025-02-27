//
// DownloadManager.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import CryptoKit

/// Manages downloading of podcast episodes.
/// This singleton class uses URLSession to download episodes and tracks their download states.
/// It handles creating required directories, monitoring download progress, and moving downloaded files.
class DownloadManager: ObservableObject {
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
    
    /// Private initializer to enforce singleton pattern.
    private init() {
        // Ensure required directories are available on initialization.
        createRequiredDirectories()
    }
    
    /// Creates necessary directories (Downloads and tmp) inside the user's document directory.
    private func createRequiredDirectories() {
        let fileManager = FileManager.default
        // Obtain the user's document directory.
        let containerURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsURL = containerURL.appendingPathComponent("Downloads")
        let tmpURL = containerURL.appendingPathComponent("tmp")
        
        do {
            // Create the Downloads directory if it doesn't exist.
            if !fileManager.fileExists(atPath: downloadsURL.path) {
                try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
                print("Created Downloads directory at: \(downloadsURL.path)")
            }
            
            // Create the temporary directory if it doesn't exist.
            if !fileManager.fileExists(atPath: tmpURL.path) {
                try fileManager.createDirectory(at: tmpURL, withIntermediateDirectories: true)
                print("Created tmp directory at: \(tmpURL.path)")
            }
        } catch {
            print("Error creating directories: \(error)")
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
                print("Created Downloads directory at: \(downloadsDir.path)")
            } catch {
                print("Error creating Downloads directory: \(error)")
            }
        }
        
        // Use SHA256 of the episode URL to generate a unique filename.
        let urlString = episode.url.absoluteString
        let hash = sha256(urlString)
        let ext = episode.url.pathExtension
        let fileName = hash + (ext.isEmpty ? "" : ".\(ext)")
        return downloadsDir.appendingPathComponent(fileName)
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
            print("Episode is already being downloaded or has been downloaded")
            return
        }
        
        print("Starting download for episode: \(episode.title)")
        downloadStates[key] = .downloading(progress: 0.0)
        
        // Create a download task for the episode.
        let task = URLSession.shared.downloadTask(with: episode.url) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            // Handle error scenario.
            if let error = error {
                print("Download error for episode '\(episode.title)': \(error)")
                DispatchQueue.main.async {
                    self.downloadStates[key] = .failed(error)
                }
                return
            }
            
            // Ensure a temporary URL is provided.
            guard let tempURL = tempURL else {
                print("No temporary URL provided for downloaded file")
                DispatchQueue.main.async {
                    self.downloadStates[key] = .failed(NSError(domain: "DownloadManager", code: -1))
                }
                return
            }
            
            let fileManager = FileManager.default
            let containerURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let downloadsURL = containerURL.appendingPathComponent("Downloads")
            
            // Generate destination filename using SHA256 hash with a ".mp3" extension.
            let filename = self.sha256(episode.url.absoluteString) + ".mp3"
            let destinationURL = downloadsURL.appendingPathComponent(filename)
            
            do {
                // Remove any existing file at the destination.
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                
                // Move the downloaded file from the temporary location to the final destination.
                try fileManager.moveItem(at: tempURL, to: destinationURL)
                print("Successfully moved downloaded file to: \(destinationURL.path)")
                
                DispatchQueue.main.async {
                    self.downloadStates[key] = .downloaded(destinationURL)
                }
            } catch {
                print("Error moving file for episode '\(episode.title)': \(error)")
                print("Temp URL: \(tempURL.path)")
                print("Destination URL: \(destinationURL.path)")
                
                // Fallback: Try copying the file instead of moving.
                do {
                    try fileManager.copyItem(at: tempURL, to: destinationURL)
                    print("Successfully copied file using fallback method")
                    
                    DispatchQueue.main.async {
                        self.downloadStates[key] = .downloaded(destinationURL)
                    }
                } catch {
                    print("Fallback copy also failed: \(error)")
                    DispatchQueue.main.async {
                        self.downloadStates[key] = .failed(error)
                    }
                }
            }
        }
        
        // Observe download progress and update the download state accordingly.
        progressObservations[key] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadStates[key] = .downloading(progress: progress.fractionCompleted)
            }
        }
        
        downloadTasks[key] = task
        task.resume()
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
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
                print("Removed downloaded file for episode '\(episode.title)' at: \(destinationURL.path)")
            }
            // Explicitly set the state to .none after removal.
            downloadStates[key] = DownloadManager.DownloadState.none
        } catch {
            print("Error removing downloaded episode '\(episode.title)': \(error)")
        }
    }
    
    /// Returns the local file URL for a downloaded episode, if it exists.
    /// - Parameter episode: The podcast episode to check.
    /// - Returns: The local URL if the episode is downloaded; otherwise, nil.
    func localURL(for episode: PodcastEpisode) -> URL? {
        let key = episode.url.absoluteString
        if case let .downloaded(url) = downloadStates[key] {
            return url
        }
        return nil
    }
    
    deinit {
        // Clean up all progress observations when the DownloadManager is deallocated.
        progressObservations.values.forEach { $0.invalidate() }
        progressObservations.removeAll()
    }
}
