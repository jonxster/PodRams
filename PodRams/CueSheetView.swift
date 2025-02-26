//
//  CueSheetView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI
import AVFoundation
import AppKit  // Needed for NSCursor

struct CueSheetView: View {
    @Binding var cue: [PodcastEpisode]
    @Binding var isCuePlaying: Bool
    @Binding var selectedEpisodeIndex: Int?
    @ObservedObject var audioPlayer: AudioPlayer
    @Environment(\.dismiss) var dismiss

    @State private var draggedEpisode: PodcastEpisode?

    var body: some View {
        VStack {
            Text("Cue")
                .font(.title)
                .padding()

            List {
                ForEach(Array(cue.enumerated()), id: \.offset) { index, episode in
                    CueRowView(episode: episode)
                        .onDrag {
                            self.draggedEpisode = episode
                            return NSItemProvider(object: episode.title as NSString)
                        }
                        .onDrop(of: [.text],
                                delegate: CueDropDelegate(item: episode, cue: $cue, draggedEpisode: $draggedEpisode))
                        .onTapGesture {
                            selectedEpisodeIndex = index
                            isCuePlaying = true
                            audioPlayer.playAudio(url: episode.url)
                            dismiss()
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
            }

            Text("Total Play Time: \(formatTotalTime(totalDuration()))")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            debugDurations()
            updateMissingDurations()
        }
    }

    private func totalDuration() -> Double {
        let total = cue.reduce(0.0) { (result, episode) in
            let duration = episode.duration ?? 0.0
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

    private func debugDurations() {
        print("Cue contents:")
        for (index, episode) in cue.enumerated() {
            print("Episode \(index): '\(episode.title)' - Duration: \(episode.duration ?? -1) seconds")
        }
    }

    private func updateMissingDurations() {
        guard !cue.isEmpty else { return }
        Task {
            for index in cue.indices {
                if cue[index].duration == nil || cue[index].duration == 0 {
                    do {
                        let duration = try await fetchDuration(from: cue[index].url)
                        if duration > 0 {
                            await MainActor.run {
                                cue[index].duration = duration
                                PersistenceManager.saveCue(cue, feedUrl: cue[index].feedUrl ?? "unknown")
                                print("Updated duration for '\(cue[index].title)' to \(duration) seconds")
                            }
                        }
                    } catch {
                        print("Failed to fetch duration for '\(cue[index].title)': \(error)")
                    }
                }
            }
        }
    }

    private func fetchDuration(from url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0.0
    }
}

struct CueRowView: View {
    let episode: PodcastEpisode
    var body: some View {
        HStack {
            if let podcastName = episode.podcastName {
                Text("\(podcastName) – \(episode.title)")
            } else {
                Text(episode.title)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CueDropDelegate: DropDelegate {
    let item: PodcastEpisode
    @Binding var cue: [PodcastEpisode]
    @Binding var draggedEpisode: PodcastEpisode?

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedEpisode, dragged != item,
              let fromIndex = cue.firstIndex(of: dragged),
              let toIndex = cue.firstIndex(of: item) else { return }

        withAnimation {
            cue.move(fromOffsets: IndexSet(integer: fromIndex),
                     toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedEpisode = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}
