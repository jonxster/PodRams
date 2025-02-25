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
        
        /// Implements equality for DownloadState
        static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.downloading, .downloading):
                return true
            case let (.downloaded(lhsURL), .downloaded(rhsURL)):
                return lhsURL == rhsURL
            default:
                return false
            }
        }
    }
    
    /// Dictionary to store download states, keyed by episode URL string
    /// Uses non-optional DownloadState values
    @Published var downloadStates: [String: DownloadState] = [:]
    private let fileManager = FileManager.default
    
    private init() {}
    
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
        do {
            try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Error creating Downloads directory: \(error)")
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
        let key = episode.url.absoluteString
        
        // Safely unwrap the current state to check if downloading or downloaded
        if let state = downloadStates[key] {
            if state == .downloading {
                return
            }
            if case .downloaded = state {
                return
            }
        }
        
        // Set state to downloading
        downloadStates[key] = .downloading
        print("Starting download for episode: \(episode.title)")
        
        let url = episode.url
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("Download error for episode '\(episode.title)': \(error)")
                    // Set to .none explicitly
                    self.downloadStates[key] = DownloadManager.DownloadState.none
                    return
                }
                guard let tempURL = tempURL else {
                    print("No file URL for downloaded episode '\(episode.title)'")
                    // Set to .none explicitly
                    self.downloadStates[key] = DownloadManager.DownloadState.none
                    return
                }
                let destinationURL = self.localFileURL(for: episode)
                do {
                    // Check if the destination file already exists and remove it
                    if self.fileManager.fileExists(atPath: destinationURL.path) {
                        try self.fileManager.removeItem(at: destinationURL)
                    }
                    // Move the downloaded file to the destination
                    try self.fileManager.moveItem(at: tempURL, to: destinationURL)
                    self.downloadStates[key] = .downloaded(destinationURL)
                    print("Episode '\(episode.title)' downloaded to: \(destinationURL.path)")
                } catch {
                    print("Error moving file for episode '\(episode.title)': \(error)")
                    // Set to .none explicitly
                    self.downloadStates[key] = DownloadManager.DownloadState.none
                }
            }
        }
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
