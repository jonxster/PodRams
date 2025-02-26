//
//  ProgressBarView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

import SwiftUI

struct ProgressBarView: View {
    var currentTime: Double
    var duration: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.clear)
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: geo.size.width * CGFloat(duration > 0 ? currentTime / duration : 0))
            }
            .cornerRadius(4)
            .overlay(
                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.trailing, 4),
                alignment: .trailing
            )
            // Make entire area tappable.
            .contentShape(Rectangle())
            // Use onChanged so dragging or tapping immediately seeks.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                        onSeek(fraction * duration)
                    }
            )
        }
        .frame(height: 20)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
