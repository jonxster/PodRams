//
//  SettingsView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-24.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @AppStorage("doubleSpeedPlayback") private var doubleSpeedEnabled: Bool = false
    @AppStorage("reduceLoudSounds") private var reduceLoudSounds: Bool = false
    @AppStorage("audioPan") private var audioPan: Double = 0.5 // 0.5 is center
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GlassEffectContainer(spacing: 24) {
            VStack(spacing: 16) {
                toggleRow(title: "Play at 2× speed", binding: $doubleSpeedEnabled)
                toggleRow(title: "Reduce loud sounds", binding: $reduceLoudSounds)
            }
            .padding(20)
            .background(sectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            eqSection

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 340)
        .background(AppTheme.color(.background, in: currentMode))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            audioPlayer.setPlaybackRate(doubleSpeedEnabled ? 2.0 : 1.0)
        }
        .onChange(of: doubleSpeedEnabled) { _, newValue in
            audioPlayer.setPlaybackRate(newValue ? 2.0 : 1.0)
        }
    }
}

private extension SettingsView {
    var currentMode: AppTheme.Mode {
        colorScheme == .dark ? .dark : .light
    }

    var primaryText: Color {
        AppTheme.color(.primaryText, in: currentMode)
    }

    var secondaryText: Color {
        AppTheme.color(.secondaryText, in: currentMode)
    }

    var sectionBackground: Color {
        AppTheme.color(.surface, in: currentMode).opacity(colorScheme == .dark ? 0.9 : 1)
    }

    var panStatusDescription: String {
        let offset = audioPan - 0.5
        if abs(offset) < 0.005 {
            return "Center"
        }
        let percentage = Int(abs(offset) * 200)
        return offset < 0 ? "\(percentage)% Left" : "\(percentage)% Right"
    }

    func toggleRow(title: String, binding: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .foregroundColor(primaryText)
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                .labelsHidden()
        }
    }

    var eqSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.accent)
                Text("Audio Balance")
                    .font(.headline)
                    .foregroundColor(primaryText)
                Spacer()
                Text(panStatusDescription)
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
                    .monospacedDigit()
            }

            LiquidGlassSlider(
                value: $audioPan,
                range: 0...1,
                tint: AppTheme.accent,
                onEditingChanged: { editing in
                    if !editing && abs(audioPan - 0.5) < 0.05 {
                        audioPan = 0.5
                    }
                    NotificationCenter.default.post(
                        name: .audioPanChanged,
                        object: nil,
                        userInfo: ["pan": audioPan]
                    )
                }
            )

            HStack {
                Text("Left")
                    .font(.caption)
                    .foregroundColor(secondaryText)
                Spacer()
                Text("Center")
                    .font(.caption)
                    .foregroundColor(secondaryText)
                    .opacity(abs(audioPan - 0.5) < 0.001 ? 1 : 0.4)
                Spacer()
                Text("Right")
                    .font(.caption)
                    .foregroundColor(secondaryText)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .glassEffect(.regular.tint(AppTheme.accent.opacity(0.25)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LiquidGlassSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var tint: Color
    var onEditingChanged: (Bool) -> Void
    
    @GestureState private var isTracking = false
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let knobDiameter: CGFloat = 22
            let trackHeight: CGFloat = 12
            let fraction = fraction(for: value, in: range)
            let rawCenter = CGFloat(fraction) * width
            let cappedCenter = clamp(rawCenter, lower: knobDiameter / 2, upper: width - knobDiameter / 2)
            let effectiveTint = isEnabled ? tint : AppTheme.secondaryText
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.surface)
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.secondaryText.opacity(0.12), lineWidth: 0.8)
                    )
                    .frame(height: trackHeight)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [effectiveTint.opacity(0.55), effectiveTint.opacity(0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(cappedCenter, knobDiameter * 0.55), height: trackHeight)
                    .opacity(0.85)
                Circle()
                    .fill(AppTheme.surface)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.primaryText.opacity(0.8), effectiveTint.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(AppTheme.secondaryText.opacity(0.3), lineWidth: 0.8)
                    )
                    .shadow(color: effectiveTint.opacity(0.35), radius: 5, x: 0, y: 2)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: cappedCenter - knobDiameter / 2)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTracking) { _, state, _ in
                        if !state {
                            state = true
                            onEditingChanged(true)
                        }
                    }
                    .onChanged { gesture in
                        let newValue = value(for: gesture.location.x, width: width, range: range)
                        if newValue != value {
                            withAnimation(.easeOut(duration: 0.12)) {
                                value = newValue
                            }
                        }
                    }
                    .onEnded { gesture in
                        let finalValue = value(for: gesture.location.x, width: width, range: range)
                        withAnimation(.easeOut(duration: 0.12)) {
                            value = finalValue
                        }
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio Balance")
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                withAnimation(.easeOut(duration: 0.12)) {
                    value = min(range.upperBound, value + step)
                }
            case .decrement:
                withAnimation(.easeOut(duration: 0.12)) {
                    value = max(range.lowerBound, value - step)
                }
            default:
                break
            }
            onEditingChanged(true)
            onEditingChanged(false)
        }
    }
    
    private var accessibilityValueText: String {
        let offset = value - (range.lowerBound + range.span / 2)
        if abs(offset) < 0.01 {
            return "Centered"
        }
        let percent = Int(abs(offset) / range.span * 200)
        return offset < 0 ? "\(percent) percent left" : "\(percent) percent right"
    }
    
    private func fraction(for currentValue: Double, in bounds: ClosedRange<Double>) -> Double {
        let clamped = min(max(currentValue, bounds.lowerBound), bounds.upperBound)
        guard bounds.span > 0 else { return 0 }
        return (clamped - bounds.lowerBound) / bounds.span
    }
    
    private func value(for location: CGFloat, width: CGFloat, range: ClosedRange<Double>) -> Double {
        guard width > 0 else { return range.lowerBound }
        let clampedX = min(max(location, 0), width)
        let ratio = Double(clampedX / width)
        return range.lowerBound + ratio * range.span
    }
    
    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return value }
        return min(max(value, lower), upper)
    }
}

private extension ClosedRange where Bound == Double {
    var span: Double { upperBound - lowerBound }
}
