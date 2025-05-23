import SwiftUI

/// A simplified version of EpisodeRow without hover animations or play/pause icons
/// Used in the subscription view
struct SimpleEpisodeRow: View {
    let episode: PodcastEpisode
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var cueState = CueState.shared // Use the shared instance
    
    /// Gets the current download state for this episode
    private var downloadState: DownloadManager.DownloadState {
        return downloadManager.downloadStates[episode.url.absoluteString] ?? DownloadManager.DownloadState.none
    }
    
    /// Determines if this episode is in the cue
    private var isInCue: Bool {
        let result = cueState.cue.contains { $0.url.absoluteString == episode.url.absoluteString }
        print("SimpleEpisodeRow: Checking if episode \(episode.title) is in cue: \(result)")
        return result
    }
    
    var body: some View {
        HStack(spacing: 8) {
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
                            .foregroundColor(isPlaying ? (colorScheme == .dark ? .accentColor : .black) : .primary)
                            .font(isPlaying ? .body.bold() : .body)
                            .frame(minWidth: 100, alignment: .leading) // Ensure minimum width
                        
                        if let podcastName = episode.podcastName {
                            Text(podcastName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        // Show duration if available
                        if let duration = episode.duration {
                            Text(formatDuration(duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading) // Flexible width with minimum
                    
                    Spacer(minLength: 8) // Ensure minimum spacing before buttons
                }
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .frame(minWidth: 180) // Ensure minimum width for the entire button
            
            // Debug print to check the download state (outside the view builder)
            let _ = print("SimpleEpisodeRow: Episode \(episode.title) has state: \(String(describing: downloadState))")
            
            // Show download progress indicator or ellipsis menu (outside the button)
            if case .downloading(let progress) = downloadState {
                // Show hoverable download progress indicator when downloading
                let _ = print("SimpleEpisodeRow: Showing hoverable progress indicator for \(episode.title): \(progress)")
                HoverableDownloadIndicator(
                    episode: episode,
                    progress: progress,
                    isPaused: false
                )
                .frame(width: 20, height: 20)
            } else if case let .paused(progress, _) = downloadState {
                // Show hoverable download progress indicator when paused
                let _ = print("SimpleEpisodeRow: Showing paused progress indicator for \(episode.title): \(progress)")
                HoverableDownloadIndicator(
                    episode: episode,
                    progress: progress,
                    isPaused: true
                )
                .frame(width: 20, height: 20)
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
                    switch downloadState {
                    case .none:
                        Button(action: {
                            print("SimpleEpisodeRow: Starting download for \(episode.title)")
                            downloadManager.downloadEpisode(episode)
                        }) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    case .downloaded:
                        Button(action: {
                            print("SimpleEpisodeRow: Removing download for \(episode.title)")
                            downloadManager.removeDownload(for: episode)
                        }) {
                            Label("Delete download", systemImage: "trash")
                        }
                    case .paused:
                        Button(action: {
                            print("SimpleEpisodeRow: Resuming download for \(episode.title)")
                            downloadManager.resumeDownload(for: episode)
                        }) {
                            Label("Resume download", systemImage: "play.circle")
                        }
                    case .failed(_):
                        Button(action: {
                            print("SimpleEpisodeRow: Retrying download for \(episode.title)")
                            downloadManager.downloadEpisode(episode)
                        }) {
                            Label("Retry download", systemImage: "arrow.clockwise")
                        }
                    case .downloading(_):
                        Button(action: {
                            print("SimpleEpisodeRow: Pausing download for \(episode.title)")
                            downloadManager.pauseDownload(for: episode)
                        }) {
                            Label("Pause download", systemImage: "pause.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden) // Hide the menu indicator arrow
                .frame(width: 20, height: 20) // Fixed size to prevent layout calculations
            }
        }
        .frame(minWidth: 220) // Ensure overall minimum width
        .padding(.vertical, 4)
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
        print("SimpleEpisodeRow: Toggling cue for episode: \(episode.title)")
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

// Create a dedicated class to manage cue state
class CueState: ObservableObject {
    static let shared = CueState() // Create a shared instance
    
    @Published var cue: [PodcastEpisode] = []
    private var isLoading = false
    
    func loadCue() {
        guard !isLoading else { 
            print("CueState: Already loading cue, skipping")
            return 
        }
        isLoading = true
        
        print("CueState: Starting to load cue")
        
        Task {
            let loadedCue = await PersistenceManager.loadCue()
            await MainActor.run {
                print("CueState: Loaded \(loadedCue.count) episodes from PersistenceManager")
                if !loadedCue.isEmpty {
                    print("CueState: First episode in cue: \(loadedCue[0].title), URL: \(loadedCue[0].url.absoluteString)")
                }
                
                self.cue = loadedCue
                self.isLoading = false
                print("CueState: Finished loading cue with \(loadedCue.count) episodes")
            }
        }
    }
    
    func toggleCue(for episode: PodcastEpisode) {
        guard !isLoading else { return }
        isLoading = true
        
        print("CueState: Starting toggleCue for episode: \(episode.title)")
        
        Task {
            // Load the latest cue data
            let latestCue = await PersistenceManager.loadCue()
            print("CueState: Loaded cue with \(latestCue.count) episodes")
            
            await MainActor.run {
                // Update our local cue with the latest data
                self.cue = latestCue
                
                // Check if the episode is in the cue
                let isInCue = latestCue.contains { $0.url.absoluteString == episode.url.absoluteString }
                print("CueState: Episode \(episode.title) is in cue: \(isInCue)")
                
                // Now perform the toggle operation
                if isInCue {
                    print("CueState: Removing episode from cue: \(episode.title)")
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
                            print("CueState: Using first episode's feedUrl for saving: \(effectiveFeedUrl)")
                        } else {
                            effectiveFeedUrl = "unknown"
                            print("CueState: Using default feedUrl for saving: \(effectiveFeedUrl)")
                        }
                        
                        PersistenceManager.saveCue(updatedCue, feedUrl: effectiveFeedUrl)
                        
                        print("CueState: Successfully removed episode from cue: \(episode.title)")
                    }
                } else {
                    print("CueState: Adding episode to cue: \(episode.title)")
                    // Add to cue
                    var newEpisode = episode
                    
                    // Ensure the episode has a podcast name
                    if newEpisode.podcastName == nil {
                        newEpisode.podcastName = "Unknown Podcast"
                        print("CueState: Set podcast name to 'Unknown Podcast' for episode: \(episode.title)")
                    } else {
                        print("CueState: Using existing podcast name: \(newEpisode.podcastName!) for episode: \(episode.title)")
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
                        print("CueState: Using first episode's feedUrl for saving: \(effectiveFeedUrl)")
                    } else {
                        effectiveFeedUrl = "unknown"
                        print("CueState: Using default feedUrl for saving: \(effectiveFeedUrl)")
                    }
                    
                    PersistenceManager.saveCue(updatedCue, feedUrl: effectiveFeedUrl)
                    
                    print("CueState: Successfully added episode to cue: \(episode.title)")
                }
                
                // Clear the cache to ensure all views reload the latest data
                PersistenceManager.clearCueCache()
                
                // Notify other components about the cue update
                NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                
                self.isLoading = false
                print("CueState: Completed toggleCue for episode: \(episode.title)")
            }
        }
    }
} 