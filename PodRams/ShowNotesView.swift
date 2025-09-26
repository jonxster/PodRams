import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Popover content that displays show notes for the currently playing episode.
struct ShowNotesView: View {
    let episodeTitle: String
    let isLoading: Bool
    let notes: AttributedString

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Show Notes")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppTheme.primaryText)
                Text(episodeTitle.isEmpty ? "" : episodeTitle)
                    .font(.headline)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(AppTheme.accent)
                    Text("Loading show notes...")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.secondaryText)
                }
            } else {
                ScrollView {
                    Text(notes)
                        .font(.body)
                        .foregroundColor(AppTheme.primaryText)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.bottom, 8)
                        .environment(\.openURL, OpenURLAction { url in
                            #if os(macOS)
                            NSWorkspace.shared.open(url)
                            #elseif canImport(UIKit)
                            UIApplication.shared.open(url)
                            #endif
                            return .handled
                        })
                }
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
    }
}

struct ShowNotesView_Previews: PreviewProvider {
    static var previews: some View {
        ShowNotesView(
            episodeTitle: "Sample Episode",
            isLoading: false,
            notes: AttributedString("Sample show notes content.")
        )
        .previewLayout(.sizeThatFits)
    }
}
