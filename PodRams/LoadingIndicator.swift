import SwiftUI

struct LoadingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.blue, lineWidth: 2)
            .frame(width: 16, height: 16)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// For cases where we want to show determinate progress
struct DeterminateLoadingIndicator: View {
    let progress: Double
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
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 16, height: 16)
                .rotationEffect(Angle(degrees: -90))
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .onAppear {
                    withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        LoadingIndicator()
        DeterminateLoadingIndicator(progress: 0.7)
    }
    .padding()
} 