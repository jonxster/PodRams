@@ struct ProgressBarView: View {
            .overlay(
                Text(Self.timerText(currentTime: currentTime, duration: duration))
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.trailing, 4),
                alignment: .trailing
            )

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // New: public static function to compute the timer text.
    public static func timerText(currentTime: Double, duration: Double) -> String {
        func formatTime(_ seconds: Double) -> String {
            guard seconds.isFinite, seconds > 0 else { return "00:00" }
            let totalSeconds = Int(seconds)
            let minutes = totalSeconds / 60
            let secs = totalSeconds % 60
            return String(format: "%02d:%02d", minutes, secs)
        }
        let remaining = max(duration - currentTime, 0)
        return "\(formatTime(remaining)) of \(formatTime(duration)) remaining"
    }
} 