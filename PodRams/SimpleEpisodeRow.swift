import SwiftUI

/// A simplified version of EpisodeRow without hover animations or play/pause icons
/// Used in the subscription view
struct SimpleEpisodeRow: View {
    let episode: PodcastEpisode
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var cue: [PodcastEpisode] = []
    
    /// Gets the current download state for this episode
    private var downloadState: DownloadManager.DownloadState {
        return downloadManager.downloadStates[episode.url.absoluteString] ?? .none
    }
    
    /// Determines if this episode is in the cue
    private var isInCue: Bool {
        return cue.contains { $0.url.absoluteString == episode.url.absoluteString }
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
                    
                    // Episode title and podcast name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .lineLimit(1)
                            .foregroundColor(isPlaying ? .blue : .primary)
                            .font(isPlaying ? .body.bold() : .body)
                        
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
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            // Show download progress indicator or ellipsis menu (outside the button)
            if case .downloading(let progress) = downloadState {
                // Show download progress indicator when downloading
                DeterminateLoadingIndicator(progress: progress)
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
                    
                    Divider()
                    
                    // Download option - show different options based on download state
                    switch downloadState {
                    case .none:
                        Button(action: {
                            downloadManager.downloadEpisode(episode)
                        }) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    case .downloaded:
                        Button(action: {
                            downloadManager.removeDownload(for: episode)
                        }) {
                            Label("Delete download", systemImage: "trash")
                        }
                    case .failed:
                        Button(action: {
                            downloadManager.downloadEpisode(episode)
                        }) {
                            Label("Retry download", systemImage: "arrow.clockwise")
                        }
                    case .downloading:
                        // No action for downloading state
                        EmptyView()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden) // Hide the menu indicator arrow
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            // Load the cue when the view appears
            Task {
                cue = await PersistenceManager.loadCue()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CueUpdated"))) { _ in
            // Update the cue when it changes elsewhere in the app
            Task {
                cue = await PersistenceManager.loadCue()
            }
        }
    }
    
    /// Toggles whether this episode is in the cue
    private func toggleCue() {
        if isInCue {
            // Remove from cue
            if let idx = cue.firstIndex(where: { $0.url.absoluteString == episode.url.absoluteString }) {
                var updatedCue = cue
                updatedCue.remove(at: idx)
                cue = updatedCue
                PersistenceManager.saveCue(cue, feedUrl: episode.feedUrl)
                NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
            }
        } else {
            // Add to cue
            var newEpisode = episode
            
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
            var updatedCue = cue
            updatedCue.append(newEpisode)
            cue = updatedCue
            PersistenceManager.saveCue(cue, feedUrl: episode.feedUrl)
            NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
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
        let remainingSeconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }
    }
} 