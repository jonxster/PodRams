//
// DownloadButton.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI
import OSLog

private let downloadButtonLogger = AppLogger.downloads

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
        logDownloadState(downloadState)

        return Button(action: {
            // Perform an action based on the current download state.
            switch downloadState {
            case .none:
                // Start downloading the episode if not already in progress.
                downloadButtonLogger.info("DownloadButton: Starting download for \(episode.title, privacy: .public)")
                downloadManager.downloadEpisode(episode)
            case .downloaded:
                // Remove the downloaded file if the episode is already downloaded.
                downloadButtonLogger.info("DownloadButton: Removing download for \(episode.title, privacy: .public)")
                downloadManager.removeDownload(for: episode)
            case .downloading:
                // No action for the button itself when downloading - pause/resume is handled by hover indicator
                downloadButtonLogger.debug("DownloadButton: Episode \(episode.title, privacy: .public) is currently downloading")
                break
            case .paused:
                // Resume download when clicking the main button for paused downloads
                downloadButtonLogger.info("DownloadButton: Resuming download for \(episode.title, privacy: .public)")
                downloadManager.resumeDownload(for: episode)
            case .failed:
                // Retry downloading the episode if a previous download attempt failed.
                downloadButtonLogger.info("DownloadButton: Retrying download for \(episode.title, privacy: .public)")
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
                    // Show a hoverable progress indicator with pause/resume functionality.
                    progressIndicator(progress: progress, isPaused: false)
                case .paused(let progress, _):
                    // Show a hoverable progress indicator in paused state with resume functionality.
                    progressIndicator(progress: progress, isPaused: true)
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
        // Disable button interaction when download is in progress to let hover indicator handle it
        .disabled(downloadState.isDownloadInProgress)
    }
}

// Extension to help determine if download is in progress
extension DownloadManager.DownloadState {
    var isDownloadInProgress: Bool {
        switch self {
        case .downloading, .paused:
            return true
        default:
            return false
        }
    }
}

private extension DownloadButton {
    func logDownloadState(_ state: DownloadManager.DownloadState) {
        let description = String(describing: state)
        downloadButtonLogger.debug("DownloadButton: Episode \(episode.title, privacy: .public) has state: \(description, privacy: .public)")
    }

    func logDownloadProgress(_ progress: Double, isPaused: Bool) {
        let status = isPaused ? "paused" : "active"
        downloadButtonLogger.debug("DownloadButton: Showing \(status, privacy: .public) progress indicator for \(episode.title, privacy: .public): \(progress, privacy: .public)")
    }

    func progressIndicator(progress: Double, isPaused: Bool) -> some View {
        logDownloadProgress(progress, isPaused: isPaused)
        return HoverableDownloadIndicator(
            episode: episode,
            progress: progress,
            isPaused: isPaused
        )
        .frame(width: 20, height: 20)
    }
}
