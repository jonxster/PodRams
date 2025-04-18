//
// DownloadButton.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI

/// A view representing a button for downloading or managing a podcast episode.
/// The button's appearance and action depend on the episode's current download state.
struct DownloadButton: View {
    /// The podcast episode associated with this download button.
    let episode: PodcastEpisode
    /// Observes the shared download manager to track download state changes.
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        // Retrieve the download state for this episode using its URL as the key.
        // If no state exists, default to .none.
        let downloadState = downloadManager.downloadStates[episode.url.absoluteString] ?? DownloadManager.DownloadState.none
        
        // Debug print to check the download state (outside the view builder)
        let _ = print("DownloadButton: Episode \(episode.title) has state: \(String(describing: downloadState))")
        
        Button(action: {
            // Perform an action based on the current download state.
            switch downloadState {
            case .none:
                // Start downloading the episode if not already in progress.
                print("DownloadButton: Starting download for \(episode.title)")
                downloadManager.downloadEpisode(episode)
            case .downloaded:
                // Remove the downloaded file if the episode is already downloaded.
                print("DownloadButton: Removing download for \(episode.title)")
                downloadManager.removeDownload(for: episode)
            case .downloading:
                // No action defined for canceling an ongoing download; future cancel functionality could be added here.
                print("DownloadButton: Episode \(episode.title) is currently downloading")
                break
            case .failed:
                // Retry downloading the episode if a previous download attempt failed.
                print("DownloadButton: Retrying download for \(episode.title)")
                downloadManager.downloadEpisode(episode)
            }
        }) {
            // Update the button's content based on the download state.
            Group {
                switch downloadState {
                case .none:
                    // Show a download icon when no download is in progress.
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                case .downloading(let progress):
                    // Show a determinate loading indicator with the current progress.
                    // Log outside the view builder
                    let _ = print("DownloadButton: Showing progress indicator for \(episode.title): \(progress)")
                    DeterminateLoadingIndicator(progress: progress)
                case .downloaded:
                    // Show a trash icon to indicate the option to remove the download.
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                case .failed:
                    // Show an error icon when the download has failed.
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
            }
        }
        // Use a plain button style for consistency with other buttons
        .buttonStyle(PlainButtonStyle())
    }
}
