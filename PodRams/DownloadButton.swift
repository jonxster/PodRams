//
//  DownloadButton.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//
import SwiftUI

struct DownloadButton: View {
    let episode: PodcastEpisode
    @ObservedObject var downloadManager = DownloadManager.shared
    
    var body: some View {
        Group {
            switch downloadManager.downloadStates[episode.url.absoluteString] ?? .none {
            case .downloading:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.5)
                    .frame(width: 20, height: 20)
            case .downloaded(_):
                Button(action: {
                    downloadManager.removeDownload(for: episode)
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            case .none:
                Button(action: {
                    downloadManager.downloadEpisode(episode)
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }
}
