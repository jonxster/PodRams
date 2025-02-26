//
//  DownloadManager.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import Foundation
import Combine
import CryptoKit

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    /// Enum representing the state of a download
    enum DownloadState: Equatable {
        case none
        case downloading
        case downloaded(URL)
        case failed(Error)
        
        /// Implements equality for DownloadState
        static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.downloading, .downloading):
                return true
            case let (.downloaded(lhsURL), .downloaded(rhsURL)):
                return lhsURL == rhsURL
            case let (.failed(lhsError), .failed(rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }
    
    /// Dictionary to store download states, keyed by episode URL string
    /// Uses non-optional DownloadState values
    @Published var downloadStates: [String: DownloadState] = [:]
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let fileManager = FileManager.default
    
    private init() {
        // Create necessary directories when DownloadManager is initialized
        createRequiredDirectories()
    }
    
    private func createRequiredDirectories() {
        let fileManager = FileManager.default
        let containerURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsURL = containerURL.appendingPathComponent("Downloads")
        let tmpURL = containerURL.appendingPathComponent("tmp")
        
        do {
            // Create Downloads directory if it doesn't exist
            if !fileManager.fileExists(atPath: downloadsURL.path) {
                try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
                print("Created Downloads directory at: \(downloadsURL.path)")
            }
            
            // Create tmp directory if it doesn't exist
            if !fileManager.fileExists(atPath: tmpURL.path) {
                try fileManager.createDirectory(at: tmpURL, withIntermediateDirectories: true)
                print("Created tmp directory at: \(tmpURL.path)")
            }
        } catch {
            print("Error creating directories: \(error)")
        }
    }
    
    /// Computes SHA256 hash for a URL string to use as a unique filename
    private func sha256(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Returns the local file URL where the episode will be stored
    private func localFileURL(for episode: PodcastEpisode) -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        
        // Create the Downloads directory if it doesn't exist
        if !fileManager.fileExists(atPath: downloadsDir.path) {
            do {
                try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
                print("Created Downloads directory at: \(downloadsDir.path)")
            } catch {
                print("Error creating Downloads directory: \(error)")
            }
        }
        
        // Use SHA256 hash of the URL as the file name to ensure it's valid and unique
        let urlString = episode.url.absoluteString
        let hash = sha256(urlString)
        let ext = episode.url.pathExtension
        let fileName = hash + (ext.isEmpty ? "" : ".\(ext)")
        return downloadsDir.appendingPathComponent(fileName)
    }
    
    /// Starts downloading an episode if not already downloading or downloaded
    func downloadEpisode(_ episode: PodcastEpisode) {
        // Ensure directories exist before starting download
        createRequiredDirectories()
        
        let key = episode.url.absoluteString
        guard downloadStates[key] == nil else {
            print("Episode is already being downloaded or has been downloaded")
            return
        }
        
        print("Starting download for episode: \(episode.title)")
        downloadStates[key] = .downloading
        
        let task = URLSession.shared.downloadTask(with: episode.url) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Download error for episode '\(episode.title)': \(error)")
                DispatchQueue.main.async {
                    self.downloadStates[key] = .failed(error)
                }
                return
            }
            
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
            
            // Use the existing sha256 method instead of calling it on the string directly
            let filename = self.sha256(episode.url.absoluteString) + ".mp3"
            let destinationURL = downloadsURL.appendingPathComponent(filename)
            
            do {
                // Remove any existing file at the destination
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                
                // Move the downloaded file to its final location
                try fileManager.moveItem(at: tempURL, to: destinationURL)
                print("Successfully moved downloaded file to: \(destinationURL.path)")
                
                DispatchQueue.main.async {
                    self.downloadStates[key] = .downloaded(destinationURL)
                }
            } catch {
                print("Error moving file for episode '\(episode.title)': \(error)")
                print("Temp URL: \(tempURL.path)")
                print("Destination URL: \(destinationURL.path)")
                
                // Try copying instead of moving as a fallback
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
        
        downloadTasks[key] = task
        task.resume()
    }
    
    /// Removes a downloaded episode and updates the state
    func removeDownload(for episode: PodcastEpisode) {
        let key = episode.url.absoluteString
        let destinationURL = localFileURL(for: episode)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
                print("Removed downloaded file for episode '\(episode.title)' at: \(destinationURL.path)")
            }
            // Set to .none explicitly
            downloadStates[key] = DownloadManager.DownloadState.none
        } catch {
            print("Error removing downloaded episode '\(episode.title)': \(error)")
        }
    }
    
    /// Returns the local URL of a downloaded episode, if available
    func localURL(for episode: PodcastEpisode) -> URL? {
        let key = episode.url.absoluteString
        if case let .downloaded(url) = downloadStates[key] {
            return url
        }
        return nil
    }
}
