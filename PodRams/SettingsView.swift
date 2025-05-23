//
//  SettingsView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-24.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("skipSilence") private var skipSilence: Bool = false
    @AppStorage("reduceLoudSounds") private var reduceLoudSounds: Bool = false
    @AppStorage("audioPan") private var audioPan: Double = 0.5 // 0.5 is center
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Use HStack for custom layout with checkbox on the right
            HStack {
                Text("Skip silence in podcasts")
                Spacer() // Pushes the toggle to the right
                Toggle("", isOn: $skipSilence)
                    .labelsHidden() // Hide the toggle's default label
            }
            
            HStack {
                Text("Reduce loud sounds")
                Spacer()
                Toggle("", isOn: $reduceLoudSounds)
                    .labelsHidden()
            }
            
            VStack(alignment: .leading) {
                Text("Audio Balance")
                HStack {
                    Text("Left")
                    Slider(
                        value: $audioPan,
                        in: 0...1,
                        step: 0.01,
                        onEditingChanged: { editing in
                            if !editing && abs(audioPan - 0.5) < 0.05 {
                                // Snap to center if close
                                audioPan = 0.5
                            }
                            // Update audio panning
                            NotificationCenter.default.post(
                                name: .audioPanChanged,
                                object: nil,
                                userInfo: ["pan": audioPan]
                            )
                        }
                    )
                    Text("Right")
                }
                
                if audioPan == 0.5 {
                    Text("Center")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(audioPan < 0.5 ? "\(Int((0.5 - audioPan) * 200))% Left" : "\(Int((audioPan - 0.5) * 200))% Right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
