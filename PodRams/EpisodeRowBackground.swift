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
                    .frame(width: geo.size.width * CGFloat(duration > 0 ? currentTime / duration : 0))

            }
            .cornerRadius(4)
        }
    }
    

}
