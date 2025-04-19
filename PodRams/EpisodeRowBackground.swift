//
//  EpisodeRowBackground.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//
import SwiftUI

struct EpisodeRowBackground: View {
    var currentTime: Double
    var duration: Double
    let progressBarHeight: CGFloat = 3 // Define height for the progress bar

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background Track (thin gray capsule)
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: progressBarHeight)
                
                // Progress Segment (thin accentColor capsule)
                Capsule()
                    .fill(Color.accentColor) // Use accent color for adaptability
                    .frame(width: calculateProgressWidth(geo: geo), height: progressBarHeight)
            }
            // Center the progress bar vertically within the geometry reader space if needed
            // Or adjust the frame of the GeometryReader itself in the parent view
            // .frame(height: progressBarHeight) // Optionally constrain ZStack height
        }
        // Ensure the GeometryReader itself takes up minimal vertical space
        .frame(height: progressBarHeight)
    }
    
    // Calculate progress width with proper handling of edge cases
    private func calculateProgressWidth(geo: GeometryProxy) -> CGFloat {
        // Check for valid inputs
        guard duration > 0, duration.isFinite, currentTime.isFinite else {
            return 0
        }
        
        // Calculate ratio and clamp between 0 and 1
        let ratio = min(max(0, currentTime / duration), 1.0)
        return geo.size.width * ratio
    }
}
