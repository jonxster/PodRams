import Foundation
import OSLog

/// Represents a transcribed podcast episode entry persisted for quick recall and export.
struct TranscriptionHistoryItem: Identifiable, Codable, Equatable, Sendable {
    var id: String { episodeID }

    let episodeID: String
    let podcastTitle: String
    let episodeTitle: String
    let artworkURL: URL?
    let transcriptText: String
    let generatedAt: Date
    let feedUrl: String?
}

/// Stores and retrieves transcription history on disk while keeping a small in-memory cache.
actor TranscriptionHistoryStore {
    static let shared = TranscriptionHistoryStore()

    private let logger = AppLogger.transcription
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private var cachedItems: [TranscriptionHistoryItem] = []
    private let maxEntries = 50

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let manager = FileManager.default
            let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
            self.fileURL = documents.appendingPathComponent("transcription_history.json")
        }
    }

    /// Loads transcription history from disk or returns the in-memory cache if it has already been loaded.
    func loadHistory() async -> [TranscriptionHistoryItem] {
        if !cachedItems.isEmpty {
            return cachedItems
        }

        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([TranscriptionHistoryItem].self, from: data)
            cachedItems = normalize(decoded)
            return cachedItems
        } catch {
            logger.debug("Failed to load transcription history: \(error.localizedDescription, privacy: .public)")
            cachedItems = []
            return []
        }
    }

    /// Inserts or updates a transcription entry, trims the list to the maximum size, and persists to disk.
    @discardableResult
    func upsert(_ item: TranscriptionHistoryItem) async -> [TranscriptionHistoryItem] {
        cachedItems.removeAll { $0.id == item.id }
        cachedItems.insert(item, at: 0)
        cachedItems = normalize(cachedItems)
        persist()
        return cachedItems
    }

    /// Removes an item from history and updates disk.
    @discardableResult
    func remove(id: String) async -> [TranscriptionHistoryItem] {
        cachedItems.removeAll { $0.id == id }
        persist()
        return cachedItems
    }

    private func persist() {
        do {
            let data = try encoder.encode(cachedItems)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.debug("Failed to persist transcription history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func normalize(_ items: [TranscriptionHistoryItem]) -> [TranscriptionHistoryItem] {
        let sorted = items.sorted { lhs, rhs in
            lhs.generatedAt > rhs.generatedAt
        }
        return Array(sorted.prefix(maxEntries))
    }
}
