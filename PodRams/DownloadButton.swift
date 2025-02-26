//
//  DownloadButton.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//
import SwiftUI

struct DownloadButton: View {
    let episode: PodcastEpisode
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        let downloadState = downloadManager.downloadStates[episode.url.absoluteString] ?? .none
        
        Button(action: {
            switch downloadState {
            case .none:
                downloadManager.downloadEpisode(episode)
            case .downloaded:
                downloadManager.removeDownload(for: episode)
            case .downloading:
                // Could add cancel functionality here in the future
                break
            case .failed:
                // Could retry the download here
                downloadManager.downloadEpisode(episode)
            }
        }) {
            switch downloadState {
            case .none:
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            case .downloading:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.5)
                    .frame(width: 20, height: 20)
            case .downloaded:
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.red)
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}
