//
// HoverableDownloadIndicator.swift
// PodRams
// Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI

/// A view that shows a download progress indicator with a pause/resume button on hover
struct HoverableDownloadIndicator: View {
    /// The podcast episode associated with this download indicator
    let episode: PodcastEpisode
    /// The current download progress (0.0 to 1.0)
    let progress: Double
    /// Whether the download is currently paused
    let isPaused: Bool
    /// Observes the shared download manager to track download state changes
    @ObservedObject private var downloadManager = DownloadManager.shared
    /// Tracks whether the mouse is hovering over the indicator
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // Background progress indicator
            DeterminateLoadingIndicator(progress: progress)
                .opacity(isHovering ? 0.3 : 1.0)
            
            // Pause/Resume button that appears on hover
            if isHovering {
                Button(action: {
                    if isPaused {
                        downloadManager.resumeDownload(for: episode)
                    } else {
                        downloadManager.pauseDownload(for: episode)
                    }
                }) {
                    Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// Enhanced DeterminateLoadingIndicator that supports paused state
struct EnhancedDeterminateLoadingIndicator: View {
    let progress: Double
    let isPaused: Bool
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 16, height: 16)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(isPaused ? Color.orange : Color.blue, lineWidth: 2)
                .frame(width: 16, height: 16)
                .rotationEffect(Angle(degrees: -90))
                .rotationEffect(Angle(degrees: isPaused ? 0 : (isAnimating ? 360 : 0)))
                .onAppear {
                    if !isPaused {
                        withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
                }
                .onChange(of: isPaused) { _, newValue in
                    if newValue {
                        // Stop animation when paused
                        isAnimating = false
                    } else {
                        // Start animation when resuming
                        withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
                }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HoverableDownloadIndicator(
            episode: PodcastEpisode(
                title: "Test Episode",
                url: URL(string: "https://example.com/test.mp3")!,
                artworkURL: nil,
                duration: nil,
                showNotes: nil
            ),
            progress: 0.6,
            isPaused: false
        )
        
        EnhancedDeterminateLoadingIndicator(progress: 0.4, isPaused: true)
        EnhancedDeterminateLoadingIndicator(progress: 0.7, isPaused: false)
    }
    .padding()
} 