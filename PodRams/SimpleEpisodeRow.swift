import SwiftUI
import OSLog

private let simpleEpisodeLogger = AppLogger.ui
private let cueLogger = AppLogger.app

/// A simplified version of EpisodeRow without hover animations or play/pause icons
/// Used in the subscription view
struct SimpleEpisodeRow: View {
    let episode: PodcastEpisode
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var cueState = CueState.shared // Use the shared instance
    @State private var isHoveringRow = false
    
    /// Gets the current download state for this episode
    private var downloadState: DownloadManager.DownloadState {
        return downloadManager.downloadStates[episode.url.absoluteString] ?? DownloadManager.DownloadState.none
    }
    
    /// Determines if this episode is in the cue
    private var isInCue: Bool {
        let result = cueState.cue.contains { $0.url.absoluteString == episode.url.absoluteString }
        simpleEpisodeLogger.debug("SimpleEpisodeRow: Checking if episode \(episode.title, privacy: .public) is in cue: \(result, privacy: .public)")
        return result
    }
    
    var body: some View {
        let currentDownloadState = downloadState
        logDownloadState(currentDownloadState)

        return HStack(spacing: 8) {
            // Main content button (everything except the menu)
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    // Episode artwork or placeholder
                    CachedAsyncImage(
                        url: episode.artworkURL,
                        width: 40,
                        height: 40
                    )
                    .cornerRadius(4)
                    .frame(width: 40, height: 40) // Explicit frame to prevent negative calculations
                    
                    // Episode title and podcast name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .lineLimit(2) // Allow wrapping but limit lines
                            .foregroundColor(isPlaying ? AppTheme.primaryText : AppTheme.primaryText.opacity(0.9))
                            .font(isPlaying ? .body.bold() : .body)
                            .frame(minWidth: 100, alignment: .leading) // Ensure minimum width
                        
                        if let podcastName = episode.podcastName {
                            Text(podcastName)
                                .font(.caption)
                                .foregroundColor(isPlaying ? AppTheme.primaryText.opacity(0.85) : AppTheme.secondaryText)
                                .lineLimit(1)
                        }
                        
                        // Show duration if available
                        if let duration = episode.duration {
                            Text(formatDuration(duration))
                                .font(.caption)
                                .foregroundColor(isPlaying ? AppTheme.primaryText.opacity(0.75) : AppTheme.secondaryText.opacity(0.85))
                        }
                    }
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading) // Flexible width with minimum
                    
                    Spacer(minLength: 8) // Ensure minimum spacing before buttons
                }
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .frame(minWidth: 180) // Ensure minimum width for the entire button
            
            // Show download progress indicator or ellipsis menu (outside the button)
            if case .downloading(let progress) = currentDownloadState {
                // Show hoverable download progress indicator when downloading
                progressIndicator(progress: progress, isPaused: false)
            } else if case let .paused(progress, _) = currentDownloadState {
                // Show hoverable download progress indicator when paused
                progressIndicator(progress: progress, isPaused: true)
            } else {
                // Show ellipsis menu
                Menu {
                    // Add/Remove from cue option
                    Button(action: {
                        toggleCue()
                    }) {
                        Label(
                            isInCue ? "Remove from cue" : "Add to cue",
                            systemImage: "music.note.list"
                        )
                    }
                    
                    // Add Download All from cue option if the episode is in the cue
                    if isInCue {
                        Button(action: {
                            downloadAllFromCue()
                        }) {
                            Label("Download all from cue", systemImage: "square.and.arrow.down.on.square")
                        }
                    }
                    
                    Divider()
                    
                    // Download option - show different options based on download state
                    switch currentDownloadState {
                    case .none:
                        Button(action: {
                            simpleEpisodeLogger.info("SimpleEpisodeRow: Starting download for \(episode.title, privacy: .public)")
                            downloadManager.downloadEpisode(episode)
                        }) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    case .downloaded:
                        Button(action: {
                            simpleEpisodeLogger.info("SimpleEpisodeRow: Removing download for \(episode.title, privacy: .public)")
                            downloadManager.removeDownload(for: episode)
                        }) {
                            Label("Delete download", systemImage: "trash")
                        }
                    case .paused:
                        Button(action: {
                            simpleEpisodeLogger.info("SimpleEpisodeRow: Resuming download for \(episode.title, privacy: .public)")
                            downloadManager.resumeDownload(for: episode)
                        }) {
                            Label("Resume download", systemImage: "play.circle")
                        }
                    case .failed(_):
                        Button(action: {
                            simpleEpisodeLogger.info("SimpleEpisodeRow: Retrying download for \(episode.title, privacy: .public)")
                            downloadManager.downloadEpisode(episode)
                        }) {
                            Label("Retry download", systemImage: "arrow.clockwise")
                        }
                    case .downloading(_):
                        Button(action: {
                            simpleEpisodeLogger.info("SimpleEpisodeRow: Pausing download for \(episode.title, privacy: .public)")
                            downloadManager.pauseDownload(for: episode)
                        }) {
                            Label("Pause download", systemImage: "pause.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(isPlaying ? AppTheme.primaryText : AppTheme.secondaryText)
                        .font(.system(size: 16))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden) // Hide the menu indicator arrow
                .frame(width: 20, height: 20) // Fixed size to prevent layout calculations
            }
        }
        .frame(minWidth: 220) // Ensure overall minimum width
        .padding(.vertical, isPlaying ? 6 : 4)
        .background(rowBackground)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHoveringRow = hovering
            }
        }
        .onAppear {
            // Load the cue when the view appears
            cueState.loadCue()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CueUpdated"))) { _ in
            // Update the cue when it changes elsewhere in the app
            cueState.loadCue()
        }
    }
    
    /// Toggles whether this episode is in the cue
    private func toggleCue() {
        simpleEpisodeLogger.info("SimpleEpisodeRow: Toggling cue for episode: \(episode.title, privacy: .public)")
        cueState.toggleCue(for: episode)
    }
    
    /// Downloads all episodes in the cue
    private func downloadAllFromCue() {
        Task {
            let cueEpisodes = await PersistenceManager.loadCue()
            for episode in cueEpisodes {
                DownloadManager.shared.downloadEpisode(episode)
            }
        }
    }
    
    /// Formats the duration in seconds to a human-readable string (e.g., "45:30")
    private func formatDuration(_ seconds: Double) -> String {
        // Handle invalid or zero duration
        guard seconds > 0, seconds.isFinite else {
            return "00:00"
        }
        
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

private extension SimpleEpisodeRow {
    func logDownloadState(_ state: DownloadManager.DownloadState) {
        let description = String(describing: state)
        simpleEpisodeLogger.debug("SimpleEpisodeRow: Episode \(episode.title, privacy: .public) has state: \(description, privacy: .public)")
    }

    func logDownloadProgress(_ progress: Double, isPaused: Bool) {
        let status = isPaused ? "paused" : "active"
        simpleEpisodeLogger.debug("SimpleEpisodeRow: Showing \(status, privacy: .public) progress indicator for \(episode.title, privacy: .public): \(progress, privacy: .public)")
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

private extension SimpleEpisodeRow {
    var rowBackground: Color {
        if isPlaying { return AppTheme.hoverSurface }
        return isHoveringRow ? AppTheme.hoverSurface : AppTheme.surface
    }
}

// Create a dedicated class to manage cue state
@MainActor
final class CueState: ObservableObject {
    static let shared = CueState() // Create a shared instance
    
    @Published var cue: [PodcastEpisode] = []
    private var isLoading = false
    
    func loadCue() {
        guard !isLoading else { 
            cueLogger.debug("CueState: Already loading cue, skipping")
            return 
        }
        isLoading = true
        
        cueLogger.info("CueState: Starting to load cue")
        
        Task {
            let loadedCue = await PersistenceManager.loadCue()
            await MainActor.run {
                cueLogger.info("CueState: Loaded \(loadedCue.count, privacy: .public) episodes from PersistenceManager")
                if !loadedCue.isEmpty {
                    let firstEpisode = loadedCue[0]
                    cueLogger.debug("CueState: First episode in cue: \(firstEpisode.title, privacy: .private), URL: \(firstEpisode.url.absoluteString, privacy: .private)")
                }
                
                self.cue = loadedCue
                self.isLoading = false
                cueLogger.info("CueState: Finished loading cue with \(loadedCue.count, privacy: .public) episodes")
            }
        }
    }
    
    func toggleCue(for episode: PodcastEpisode) {
        guard !isLoading else { return }
        isLoading = true
        
        cueLogger.info("CueState: Starting toggleCue for episode: \(episode.title, privacy: .private)")
        
        Task {
            // Load the latest cue data
            let latestCue = await PersistenceManager.loadCue()
            cueLogger.info("CueState: Loaded cue with \(latestCue.count, privacy: .public) episodes")
            
            await MainActor.run {
                // Update our local cue with the latest data
                self.cue = latestCue
                
                // Check if the episode is in the cue
                let isInCue = latestCue.contains { $0.url.absoluteString == episode.url.absoluteString }
                cueLogger.debug("CueState: Episode \(episode.title, privacy: .private) is in cue: \(isInCue, privacy: .public)")
                
                // Now perform the toggle operation
                if isInCue {
                    cueLogger.info("CueState: Removing episode from cue: \(episode.title, privacy: .private)")
                    // Remove from cue
                    if let idx = cue.firstIndex(where: { $0.url.absoluteString == episode.url.absoluteString }) {
                        var updatedCue = cue
                        updatedCue.remove(at: idx)
                        
                        // Update local state
                        cue = updatedCue
                        
                        // Save to persistence
                        let effectiveFeedUrl: String
                        if let feedUrl = episode.feedUrl, !feedUrl.isEmpty {
                            effectiveFeedUrl = feedUrl
                        } else if let firstEpisode = updatedCue.first, let firstFeedUrl = firstEpisode.feedUrl, !firstFeedUrl.isEmpty {
                            effectiveFeedUrl = firstFeedUrl
                            cueLogger.debug("CueState: Using first episode's feedUrl for saving: \(effectiveFeedUrl, privacy: .private)")
                        } else {
                            effectiveFeedUrl = "unknown"
                            cueLogger.debug("CueState: Using default feedUrl for saving: \(effectiveFeedUrl, privacy: .public)")
                        }
                        
                        PersistenceManager.saveCue(updatedCue, feedUrl: effectiveFeedUrl)
                        
                        cueLogger.info("CueState: Successfully removed episode from cue: \(episode.title, privacy: .private)")
                    }
                } else {
                    cueLogger.info("CueState: Adding episode to cue: \(episode.title, privacy: .private)")
                    // Add to cue
                    var newEpisode = episode
                    
                    // Ensure the episode has a podcast name
                    if newEpisode.podcastName == nil {
                        newEpisode.podcastName = "Unknown Podcast"
                        cueLogger.debug("CueState: Set podcast name to 'Unknown Podcast' for episode: \(episode.title, privacy: .private)")
                    } else {
                        if let podcastName = newEpisode.podcastName {
                            cueLogger.debug("CueState: Using existing podcast name: \(podcastName, privacy: .private) for episode: \(episode.title, privacy: .private)")
                        }
                    }
                    
                    // Generate a unique ID for the cue version of the episode
                    let cueId = "cue_\(UUID().uuidString)_\(episode.url.absoluteString)"
                    newEpisode = PodcastEpisode(
                        id: cueId,
                        title: newEpisode.title,
                        url: newEpisode.url,
                        artworkURL: newEpisode.artworkURL,
                        duration: newEpisode.duration,
                        showNotes: newEpisode.showNotes,
                        feedUrl: newEpisode.feedUrl,
                        podcastName: newEpisode.podcastName
                    )
                    
                    // Create a new array with the added episode
                    var updatedCue = cue
                    updatedCue.append(newEpisode)
                    
                    // Update local state
                    cue = updatedCue
                    
                    // Save to persistence
                    let effectiveFeedUrl: String
                    if let feedUrl = episode.feedUrl, !feedUrl.isEmpty {
                        effectiveFeedUrl = feedUrl
                    } else if let firstEpisode = updatedCue.first, let firstFeedUrl = firstEpisode.feedUrl, !firstFeedUrl.isEmpty {
                        effectiveFeedUrl = firstFeedUrl
                        cueLogger.debug("CueState: Using first episode's feedUrl for saving: \(effectiveFeedUrl, privacy: .private)")
                    } else {
                        effectiveFeedUrl = "unknown"
                        cueLogger.debug("CueState: Using default feedUrl for saving: \(effectiveFeedUrl, privacy: .public)")
                    }
                    
                    PersistenceManager.saveCue(updatedCue, feedUrl: effectiveFeedUrl)
                    
                    cueLogger.info("CueState: Successfully added episode to cue: \(episode.title, privacy: .private)")
                }
                
                // Clear the cache to ensure all views reload the latest data
                PersistenceManager.clearCueCache()
                
                // Notify other components about the cue update
                NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                
                self.isLoading = false
                cueLogger.info("CueState: Completed toggleCue for episode: \(episode.title, privacy: .private)")
            }
        }
    }
}
