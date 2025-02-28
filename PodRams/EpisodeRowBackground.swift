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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Base black background.
                Rectangle()
                    .fill(Color.clear)
                // Blue overlay fills according to progress.
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: calculateProgressWidth(geo: geo))

            }
            .cornerRadius(4)
        }
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
