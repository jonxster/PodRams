//
// CueSheetView.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI
import AVFoundation
import AppKit  // Required for managing NSCursor during hover events

/// A view that displays and manages the play queue (cue) of podcast episodes.
/// Allows users to reorder episodes via drag-and-drop, tap to play, and view total play time.
struct CueSheetView: View {
    /// Binding to the list of podcast episodes in the cue.
    @Binding var cue: [PodcastEpisode]
    /// Binding indicating whether the cue is currently being played.
    @Binding var isCuePlaying: Bool
    /// Binding to the index of the currently selected episode.
    @Binding var selectedEpisodeIndex: Int?
    /// The audio player responsible for playing episodes.
    @ObservedObject var audioPlayer: AudioPlayer
    /// Environment dismiss action to close the view.
    @Environment(\.dismiss) var dismiss
    /// Binding to the selected podcast.
    @Binding var selectedPodcast: Podcast?

    /// Local state to hold the episode being dragged during a drag-and-drop operation.
    @State private var draggedEpisode: PodcastEpisode?

    var body: some View {
        VStack {
            // Title for the cue sheet.
            Text("Cue")
                .font(.title)
                .padding()
            
            // List displaying each episode in the cue.
            List {
                // Enumerate over cue episodes to obtain both index and episode.
                ForEach(Array(cue.enumerated()), id: \.offset) { index, episode in
                    // Render each row using CueRowView.
                    CueRowView(episode: episode, cue: $cue)
                        // Enable drag: set the draggedEpisode and return an NSItemProvider.
                        .onDrag {
                            self.draggedEpisode = episode
                            return NSItemProvider(object: episode.title as NSString)
                        }
                        // Enable drop: use a custom drop delegate to handle reordering.
                        .onDrop(of: [.text],
                                delegate: CueDropDelegate(item: episode, cue: $cue, draggedEpisode: $draggedEpisode))
                        // On tap, select the episode, start cue playback, and dismiss the view.
                        .onTapGesture {
                            selectedEpisodeIndex = index
                            isCuePlaying = true
                            
                            // Ensure the episode has a podcast name before playing
                            if episode.podcastName == nil && selectedPodcast != nil {
                                var updatedEpisode = episode
                                updatedEpisode.podcastName = selectedPodcast?.title
                                
                                // Create a new array to avoid direct binding modification
                                var updatedCue = cue
                                updatedCue[index] = updatedEpisode
                                cue = updatedCue
                                
                                PersistenceManager.saveCue(cue, feedUrl: episode.feedUrl)
                                NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                                audioPlayer.playAudio(url: updatedEpisode.url)
                            } else {
                                audioPlayer.playAudio(url: episode.url)
                            }
                            dismiss()
                        }
                        // Change the cursor on hover to indicate interactivity.
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear) // Clear background for each row
                }
            }
            .listStyle(PlainListStyle()) // Use plain style to minimize default styling
            .background(Color.clear) // Clear background for the list
            .padding(.vertical, 4)
            
            // Display the total play time of all episodes in the cue.
            Text("Total Play Time: \(formatTotalTime(totalDuration()))")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    // Only show the buttons if the cue is not empty
                    !cue.isEmpty ? 
                    HStack {
                        // Download All button
                        Button(action: {
                            downloadAllEpisodes()
                        }) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .foregroundColor(.blue)
                                .opacity(0.7)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help("Download all episodes in the cue")
                        
                        Spacer().frame(width: 10)
                        
                        // Clear button
                        Button(action: {
                            clearCue()
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .opacity(0.7)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help("Clear all episodes from the cue")
                    }
                    .padding(.trailing, 20)
                    : nil,
                    alignment: .trailing
                )
        }
        // Set a minimum frame for the cue sheet.
        .frame(minWidth: 400, minHeight: 500)
        // When the view appears, print debug information and update missing episode durations.
        .onAppear {
            debugDurations()
            updateMissingDurations()
            updateMissingPodcastNames()
        }
    }
    
    /// Updates episodes in the cue that are missing podcast names.
    /// Uses the selectedPodcast title if available.
    private func updateMissingPodcastNames() {
        guard !cue.isEmpty else { return }
        
        Task {
            var updatedCue = cue
            var hasUpdates = false
            
            for index in updatedCue.indices {
                if updatedCue[index].podcastName == nil && selectedPodcast != nil {
                    updatedCue[index].podcastName = selectedPodcast?.title
                    hasUpdates = true
                }
            }
            
            if hasUpdates {
                await MainActor.run {
                    // Update the binding on the main thread
                    cue = updatedCue
                    
                    // Save the updated cue to persistent storage
                    if let feedUrl = cue.first?.feedUrl {
                        PersistenceManager.saveCue(cue, feedUrl: feedUrl)
                        NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                    }
                }
            }
        }
    }
    
    /// Calculates the total duration of all episodes in the cue.
    /// It skips invalid durations and prints warnings if necessary.
    /// - Returns: The sum of valid episode durations in seconds.
    private func totalDuration() -> Double {
        let total = cue.reduce(0.0) { (result, episode) in
            let duration = episode.duration ?? 0.0
            // Check for invalid values such as negative, NaN, or infinite durations.
            if duration < 0 || duration.isNaN || duration.isInfinite {
                print("Invalid duration for episode '\(episode.title)': \(duration)")
                return result
            }
            return result + duration
        }
        if total == 0.0 && !cue.isEmpty {
            print("Warning: Total duration is 0 despite \(cue.count) episodes in cue")
        }
        return total.isFinite ? total : 0.0
    }
    
    /// Formats a time interval (in seconds) into a human-readable string.
    /// - Parameter seconds: The total number of seconds.
    /// - Returns: A formatted string in "H:MM:SS" or "M:SS" format.
    private func formatTotalTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
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
    
    /// Prints debugging information about the durations of each episode in the cue.
    private func debugDurations() {
        print("Cue contents:")
        for (index, episode) in cue.enumerated() {
            print("Episode \(index): '\(episode.title)' - Duration: \(episode.duration ?? -1) seconds")
        }
    }
    
    /// Updates episodes in the cue that are missing valid duration information.
    /// For each episode with an unknown or zero duration, asynchronously fetch the duration
    /// using AVURLAsset and update the cue as well as persistent storage.
    private func updateMissingDurations() {
        guard !cue.isEmpty else { return }
        Task {
            var updatedCue = cue
            var hasUpdates = false
            
            for index in updatedCue.indices {
                if updatedCue[index].duration == nil || 
                   updatedCue[index].duration == 0 || 
                   !(updatedCue[index].duration?.isFinite ?? false) {
                    do {
                        let duration = try await fetchDuration(from: updatedCue[index].url)
                        // Verify the duration is valid (positive and finite)
                        if duration > 0 && duration.isFinite {
                            updatedCue[index].duration = duration
                            hasUpdates = true
                            print("Fetched duration for '\(updatedCue[index].title)': \(duration) seconds")
                        }
                    } catch {
                        print("Failed to fetch duration for '\(updatedCue[index].title)': \(error)")
                    }
                }
            }
            
            if hasUpdates {
                await MainActor.run {
                    // Update the binding on the main thread
                    cue = updatedCue
                    
                    // Save updated cue to persistent storage
                    if let feedUrl = cue.first?.feedUrl {
                        PersistenceManager.saveCue(cue, feedUrl: feedUrl)
                        NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
                        print("Updated cue with new durations and saved to persistent storage")
                    }
                }
            }
        }
    }
    
    /// Asynchronously fetches the duration of an audio asset from a given URL.
    /// - Parameter url: The URL of the audio asset.
    /// - Returns: The duration of the audio in seconds, or 0.0 if invalid.
    private func fetchDuration(from url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0.0
    }
    
    /// Clears all episodes from the cue and updates persistence.
    private func clearCue() {
        // Create a new empty array to clear the cue
        let feedUrl = cue.first?.feedUrl
        cue = []
        
        // Save the empty cue to persistence
        if let feedUrl = feedUrl {
            PersistenceManager.saveCue(cue, feedUrl: feedUrl)
            NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
        }
    }
    
    /// Downloads all episodes in the cue
    private func downloadAllEpisodes() {
        print("CueSheetView: Starting download of all episodes in cue")
        
        // Create a counter for successful downloads
        var successCount = 0
        
        // Create a task group to handle downloads
        Task {
            for episode in cue {
                // Check if the episode is already downloaded
                let currentState = DownloadManager.shared.downloadState(for: episode)
                
                if case .downloaded = currentState {
                    print("CueSheetView: Episode already downloaded: \(episode.title)")
                    successCount += 1
                    continue
                }
                
                if case .downloading = currentState {
                    print("CueSheetView: Episode already downloading: \(episode.title)")
                    continue
                }
                
                // Start the download
                print("CueSheetView: Starting download for episode: \(episode.title)")
                DownloadManager.shared.downloadEpisode(episode)
            }
            
            // Post a notification that downloads have been initiated
            await MainActor.run {
                NotificationCenter.default.post(name: Notification.Name("DownloadsInitiated"), object: nil)
            }
        }
    }
}

/// A view representing a single row in the cue list, showing the episode title and podcast name if available.
struct CueRowView: View {
    /// The podcast episode to display.
    let episode: PodcastEpisode
    /// Binding to the cue array to enable removal of episodes.
    @Binding var cue: [PodcastEpisode]
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    /// Gets the current download state for this episode
    private var downloadState: DownloadManager.DownloadState {
        return downloadManager.downloadStates[episode.url.absoluteString] ?? DownloadManager.DownloadState.none
    }
    
    /// Gets the podcast artwork URL, falling back to the episode artwork if needed
    private var podcastArtworkURL: URL? {
        if let feedUrl = episode.feedUrl,
           let podcast = PersistenceManager.loadPodcast(feedUrl: feedUrl),
           let artworkURL = podcast.feedArtworkURL {
            return artworkURL
        }
        return episode.artworkURL
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Podcast artwork
            CachedAsyncImage(
                url: podcastArtworkURL,
                width: 40,
                height: 40
            )
            .cornerRadius(4)
            
            // Episode title and podcast name
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .lineLimit(1)
                    .font(.body)
                
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
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Show download progress indicator or ellipsis menu
            if case .downloading(let progress) = downloadState {
                // Show download progress indicator when downloading
                DeterminateLoadingIndicator(progress: progress)
                    .frame(width: 20, height: 20)
            } else {
                // Show ellipsis menu
                Menu {
                    // Remove from cue option
                    Button(action: {
                        if let idx = cue.firstIndex(where: { $0.url.absoluteString == episode.url.absoluteString }) {
                            cue.remove(at: idx)
                            PersistenceManager.saveCue(cue, feedUrl: episode.feedUrl)
                        }
                    }) {
                        Label("Remove from cue", systemImage: "minus.circle")
                    }
                    
                    // Download options based on download state
                    switch downloadState {
                    case .none:
                        Button(action: {
                            print("CueRowView: Starting download for \(episode.title)")
                            downloadManager.downloadEpisode(episode)
                        }) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    case .downloaded:
                        Button(action: {
                            print("CueRowView: Removing download for \(episode.title)")
                            downloadManager.removeDownload(for: episode)
                        }) {
                            Label("Delete download", systemImage: "trash")
                        }
                    case .failed:
                        Button(action: {
                            print("CueRowView: Retrying download for \(episode.title)")
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DownloadCompleted"))) { notification in
            if let episodeUrl = notification.userInfo?["episodeUrl"] as? String,
               episodeUrl == episode.url.absoluteString {
                print("CueRowView: Received download completed notification for \(episode.title)")
            }
        }
    }
    
    /// Formats a duration in seconds to a human-readable string
    private func formatDuration(_ seconds: Double) -> String {
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

/// A custom drop delegate to handle drag-and-drop reordering of episodes in the cue.
struct CueDropDelegate: DropDelegate {
    /// The target episode item over which the dragged item is dropped.
    let item: PodcastEpisode
    /// Binding to the cue array to update the order.
    @Binding var cue: [PodcastEpisode]
    /// Binding to the currently dragged episode.
    @Binding var draggedEpisode: PodcastEpisode?

    /// Called when a dragged item enters the drop target.
    /// If valid, it moves the dragged episode to a new position within the cue.
    func dropEntered(info: DropInfo) {
        guard let dragged = draggedEpisode, dragged != item,
              let fromIndex = cue.firstIndex(of: dragged),
              let toIndex = cue.firstIndex(of: item) else { return }
        
        withAnimation {
            // Create a new array to avoid direct binding modification
            var updatedCue = cue
            let movedItem = updatedCue.remove(at: fromIndex)
            let insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
            updatedCue.insert(movedItem, at: insertIndex)
            cue = updatedCue
            
            // Add notification for cue update after reordering
            if let feedUrl = cue.first?.feedUrl {
                PersistenceManager.saveCue(cue, feedUrl: feedUrl)
                NotificationCenter.default.post(name: Notification.Name("CueUpdated"), object: nil)
            }
        }
    }

    /// Called when the drop operation is performed.
    /// Clears the dragged episode and returns true to indicate success.
    func performDrop(info: DropInfo) -> Bool {
        draggedEpisode = nil
        return true
    }

    /// Provides an updated drop proposal for the ongoing drag operation.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// Validates the drop operation; always returns true in this implementation.
    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}
