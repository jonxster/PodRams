import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionHistoryView: View {
    @Binding var items: [TranscriptionHistoryItem]
    @Binding var expandedIDs: Set<String>
    let isTranscribing: Bool
    let inProgressTitle: String?
    let errorMessage: String?
    let timestampFormatter: DateFormatter
    let onRetry: (() -> Void)?
    let onDownload: (TranscriptionHistoryItem) -> Void
    let onDelete: (TranscriptionHistoryItem) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText: String = ""

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            header
            statusBlock
            historyContent
        }
        .padding(24)
        .searchable(text: $searchText, placement: .automatic, prompt: "Search transcripts")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcriptions")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(primaryText)
                Text("Previously transcribed podcasts")
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if isTranscribing {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .tint(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcribing…")
                        .font(.headline)
                        .foregroundColor(primaryText)
                    Text(inProgressTitle ?? "Processing selected episode")
                        .font(.subheadline)
                        .foregroundColor(secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            .background(AppTheme.color(.surface, in: mode).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let errorMessage {
            VStack(spacing: 10) {
                Text("Unable to transcribe")
                    .font(.headline)
                    .foregroundColor(primaryText)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                if let onRetry {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(AppTheme.color(.surface, in: mode).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        let visibleItems = filteredItems()

        if visibleItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(secondaryText)
                if searchText.isEmpty {
                    Text("No transcriptions yet")
                        .font(.headline)
                        .foregroundColor(primaryText)
                    Text("Transcribed podcasts will appear here for quick download or removal.")
                        .font(.subheadline)
                        .foregroundColor(secondaryText)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No matching transcripts")
                        .font(.headline)
                        .foregroundColor(primaryText)
                    Text("Try a different search for podcast titles, episode names, or transcript text.")
                        .font(.subheadline)
                        .foregroundColor(secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(.top, 12)
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(visibleItems, id: \.id) { item in
                        transcriptionDisclosure(for: item)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(minHeight: 320, maxHeight: 520)
        }
    }

    private func transcriptionDisclosure(for item: TranscriptionHistoryItem) -> some View {
        let isExpanded = Binding(
            get: { expandedIDs.contains(item.id) },
            set: { expanded in
                if expanded {
                    expandedIDs.insert(item.id)
                } else {
                    expandedIDs.remove(item.id)
                }
            }
        )

        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if !item.transcriptText.isEmpty {
                    selectableTranscriptView(for: item)
                } else {
                    Text("Transcript not available.")
                        .font(.callout)
                        .foregroundColor(secondaryText)
                }

                Text(timestampFormatter.string(from: item.generatedAt))
                    .font(.footnote)
                    .foregroundColor(secondaryText)
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 12) {
                CachedAsyncImage(
                    url: item.artworkURL,
                    width: 48,
                    height: 48
                )
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.podcastTitle)
                        .font(.headline)
                        .foregroundColor(primaryText)
                        .lineLimit(1)
                    Text(item.episodeTitle)
                        .font(.subheadline)
                        .foregroundColor(secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    onDownload(item)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(primaryText)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    onDelete(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(removalTint)
                        .frame(width: 32, height: 32)
                        .background(controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .accentColor(primaryText)
        .padding(18)
        .background(rowBackground)
    }

    private var mode: AppTheme.Mode {
        colorScheme == .dark ? .dark : .light
    }

    private var primaryText: Color {
        AppTheme.color(.primaryText, in: mode)
    }

    private var secondaryText: Color {
        AppTheme.color(.secondaryText, in: mode)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppTheme.color(.surface, in: mode))
    }

    private var controlBackground: Color {
        AppTheme.color(.surface, in: mode).opacity(0.9)
    }

    private var removalTint: Color {
        colorScheme == .dark ? Color.red.opacity(0.82) : Color.red.opacity(0.72)
    }

    private func displayText(for item: TranscriptionHistoryItem) -> String {
        let limit = 12_000
        if item.transcriptText.count > limit {
            let prefix = String(item.transcriptText.prefix(limit))
            return prefix + "\n\n… transcript truncated for display. Export to view the full text."
        }
        return item.transcriptText
    }

    private func selectableTranscriptView(for item: TranscriptionHistoryItem) -> some View {
        ScrollView {
            Text(displayText(for: item))
                .font(.body)
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(minHeight: 160)
        .background(AppTheme.color(.surface, in: mode).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.color(.accent, in: mode).opacity(0.2), lineWidth: 1)
        )
        .textSelection(.enabled)
    }

    private func filteredItems() -> [TranscriptionHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        return items.filter { item in
            let haystack = [
                item.podcastTitle,
                item.episodeTitle,
                item.transcriptText
            ].joined(separator: " ").lowercased()
            return haystack.contains(query.lowercased())
        }
    }
}

struct TranscriptTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
