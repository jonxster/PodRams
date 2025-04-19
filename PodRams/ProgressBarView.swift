//
//  ProgressBarView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI

struct ProgressBarView: View {
    let currentTime: Double
    let duration: Double
    var onSeek: ((Double) -> Void)?
    @State private var isDragging = false
    @State private var dragPosition: CGFloat = 0
    
    var body: some View {
        // Wrap the bar and text in a VStack
        VStack(spacing: 4) { // Add some spacing between bar and text
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    // Progress bar
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: calculateWidth(in: geometry), height: 4)
                }
                // Removed the .overlay modifier
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragPosition = min(max(0, value.location.x), geometry.size.width)
                            let seekTime = (dragPosition / geometry.size.width) * duration
                            onSeek?(seekTime)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 4) // Keep the bar height constrained

            // Add the text below the bar and center it
            Text(timerDisplayText)
                .font(.caption)
                // Use .secondary color for less emphasis compared to the bar
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center) // Center the text
        }
        .frame(height: 30) // Keep the overall height for the container
    }
    
    /// Computes the display string for the timer.
    private var timerDisplayText: String {
        let remaining = max(duration - currentTime, 0)
        return "\(formatTime(remaining)) of \(formatTime(duration)) remaining"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" } // Handle negative and non-finite values
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs) // Always use two digits
    }

    private func calculateWidth(in geometry: GeometryProxy) -> CGFloat {
        if isDragging {
            return dragPosition
        } else if duration > 0 && duration.isFinite && currentTime.isFinite {
            // Ensure both values are finite and duration is positive
            let ratio = min(max(0, currentTime / duration), 1.0) // Clamp between 0 and 1
            return ratio * geometry.size.width
        } else {
            return 0
        }
    }
}
