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
    @AppStorage("leftPan") private var leftPan: Double = 0.5
    @AppStorage("rightPan") private var rightPan: Double = 0.5
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title)
            
            Toggle("Skip silence in podcasts", isOn: $skipSilence)
            Toggle("Reduce loud sounds", isOn: $reduceLoudSounds)
            
            HStack {
                Text("Left Panning")
                Slider(value: $leftPan, in: 0...1)
            }
            
            HStack {
                Text("Right Panning")
                Slider(value: $rightPan, in: 0...1)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
