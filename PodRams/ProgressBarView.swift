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
                
                // Do NOT add any time text here
            }
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
        .frame(height: 30)
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
