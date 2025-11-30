//
//  EpisodeTranscriptionManager.swift
//  PodRams
//
//  Created by Codex CLI on 2025-03-03.
//

import Foundation
import OSLog
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Errors that can occur while attempting to transcribe an episode.
enum EpisodeTranscriptionError: LocalizedError {
    case unsupportedPlatform
    case authorizationDenied
    case frameworkUnavailable
    case noRecognizer
    case emptyResult
    case cancelled
    case downloadFailed(underlying: Error)
    case audioPreparationFailed(underlying: Error)
    case segmentationFailed
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Transcription requires macOS with Speech recognition support."
        case .authorizationDenied:
            return "Speech recognition permission was not granted."
        case .frameworkUnavailable:
            return "Speech recognition is not available on this system."
        case .noRecognizer:
            return "No compatible speech recognizer is available."
        case .emptyResult:
            return "No transcript could be generated for this episode."
        case .cancelled:
            return "Transcription was cancelled."
        case .downloadFailed(let underlying):
            return "Failed to prepare audio for transcription: \(underlying.localizedDescription)"
        case .audioPreparationFailed(let underlying):
            return "Unable to convert audio for transcription: \(underlying.localizedDescription)"
        case .segmentationFailed:
            return "Unable to segment the audio for speech recognition."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Metadata that can be passed to the underlying speech engine.
struct EpisodeTranscriptionMetadata: Sendable {
    let episodeTitle: String
    let podcastTitle: String?
    let duration: Double?

    init(episodeTitle: String, podcastTitle: String?, duration: Double?) {
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.duration = duration
    }
}

/// Protocol implemented by the different transcription backends.
protocol EpisodeTranscribing: Sendable {
    func transcribe(preparedAudio: PreparedAudio, metadata: EpisodeTranscriptionMetadata) async throws -> String
}

/// Protocol responsible for preparing episode audio for transcription.
protocol TranscriptionAudioPreparing: Sendable {
    func prepareAudio(for url: URL, episodeID: String) async throws -> PreparedAudio
}

/// Protocol for caching transcripts in memory and on disk.
protocol TranscriptCaching: Sendable {
    func cachedTranscript(for episodeID: String) -> EpisodeTranscriptionManager.Transcript?
    func store(_ transcript: EpisodeTranscriptionManager.Transcript, for episodeID: String)
    func removeCachedTranscript(for episodeID: String)
}

/// Actor responsible for coordinating episode transcription, caching the results, and preparing audio files.
actor EpisodeTranscriptionManager {
    static let shared = EpisodeTranscriptionManager()
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    struct Transcript: Codable, Sendable {
        let text: String
        let generatedAt: Date
        let sourceEpisodeID: String
    }

    private let logger = AppLogger.transcription
    private let audioPreparer: TranscriptionAudioPreparing
    private let transcriber: EpisodeTranscribing
    private let fallbackTranscriber: EpisodeTranscribing?
    private let cache: TranscriptCaching
    private var inFlightTasks: [String: Task<Transcript, Error>] = [:]

    init(
        audioPreparer: TranscriptionAudioPreparing = DefaultTranscriptionAudioPreparer(),
        transcriber: EpisodeTranscribing? = nil,
        cache: TranscriptCaching = DiskTranscriptCache()
    ) {
        self.audioPreparer = audioPreparer
        self.cache = cache

        if let transcriber {
            self.transcriber = transcriber
            self.fallbackTranscriber = nil
            return
        }

        if #available(macOS 26.0, iOS 26.0, *), SpeechAnalyzerTranscriber.isSupported {
            self.transcriber = SpeechAnalyzerTranscriber()
            self.fallbackTranscriber = SegmentedSpeechTranscriber()
        } else {
            self.transcriber = SegmentedSpeechTranscriber()
            self.fallbackTranscriber = nil
        }
    }

    /// Returns a cached transcript if one exists.
    func cachedTranscript(for episode: PodcastEpisode) -> Transcript? {
        cache.cachedTranscript(for: episode.id)
    }

    /// Removes a cached transcript for a specific episode ID.
    func removeCachedTranscript(for episodeID: String) {
        cache.removeCachedTranscript(for: episodeID)
    }

    /// Indicates whether any transcription tasks are currently running.
    func hasInFlightTranscriptions() -> Bool {
        !inFlightTasks.isEmpty
    }

    /// Returns a transcript for the given episode, kicking off transcription if necessary.
    func transcript(for episode: PodcastEpisode) async throws -> Transcript {
        if let cached = cache.cachedTranscript(for: episode.id) {
            logger.debug("Returning cached transcript for episode \(episode.title, privacy: .private)")
            return cached
        }

        if let task = inFlightTasks[episode.id] {
            return try await task.value
        }

        let task = Task { [weak self] () -> Transcript in
            guard let self else { throw EpisodeTranscriptionError.cancelled }
            return try await self.performTranscription(for: episode)
        }

        inFlightTasks[episode.id] = task
        defer { inFlightTasks.removeValue(forKey: episode.id) }

        do {
            let transcript = try await task.value
            cache.store(transcript, for: episode.id)
            return transcript
        } catch {
            logger.error("Transcription failed for episode \(episode.title, privacy: .private): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Performs the transcription work, preparing the audio file and invoking the speech engine.
    private func performTranscription(for episode: PodcastEpisode) async throws -> Transcript {
        logger.info("Starting transcription for episode \(episode.title, privacy: .private)")

        let playbackURL = await MainActor.run {
            DownloadManager.shared.playbackURL(for: episode)
        }

        let prepared = try await audioPreparer.prepareAudio(for: playbackURL, episodeID: episode.id)
        defer {
            for url in prepared.cleanupURLs {
                cleanupTemporaryFile(at: url)
            }
        }

        let metadata = EpisodeTranscriptionMetadata(
            episodeTitle: episode.title,
            podcastTitle: episode.podcastName ?? episode.feedUrl,
            duration: episode.duration ?? prepared.duration
        )

        do {
            let text = try await transcriber.transcribe(preparedAudio: prepared, metadata: metadata)
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw EpisodeTranscriptionError.emptyResult
            }
            logger.info("Completed transcription for episode \(episode.title, privacy: .private)")
            let transcript = Transcript(text: normalized, generatedAt: Date(), sourceEpisodeID: episode.id)
            await notifyCompletion(for: transcript, episode: episode)
            return transcript
        } catch is CancellationError {
            throw EpisodeTranscriptionError.cancelled
        } catch let error as EpisodeTranscriptionError {
            if let fallbackTranscriber, shouldFallback(for: error) {
                logger.debug("Primary transcriber failed (\(error.localizedDescription, privacy: .public)); falling back to segmented transcriber.")
                let text = try await fallbackTranscriber.transcribe(preparedAudio: prepared, metadata: metadata)
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { throw EpisodeTranscriptionError.emptyResult }
                let transcript = Transcript(text: normalized, generatedAt: Date(), sourceEpisodeID: episode.id)
                await notifyCompletion(for: transcript, episode: episode)
                return transcript
            }
            throw error
        } catch {
            if let fallbackTranscriber {
                logger.debug("Primary transcriber failed (\(error.localizedDescription, privacy: .public)); falling back to segmented transcriber.")
                let text = try await fallbackTranscriber.transcribe(preparedAudio: prepared, metadata: metadata)
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { throw EpisodeTranscriptionError.emptyResult }
                let transcript = Transcript(text: normalized, generatedAt: Date(), sourceEpisodeID: episode.id)
                await notifyCompletion(for: transcript, episode: episode)
                return transcript
            }
            throw EpisodeTranscriptionError.underlying(error)
        }
    }

    private func shouldFallback(for error: EpisodeTranscriptionError) -> Bool {
        switch error {
        case .unsupportedPlatform, .frameworkUnavailable, .noRecognizer, .authorizationDenied, .downloadFailed:
            return true
        default:
            return false
        }
    }

    /// Posts a user notification when a transcription finishes.
    @MainActor
    private func notifyCompletion(for transcript: Transcript, episode: PodcastEpisode) async {
        #if canImport(UserNotifications)
        #if SWIFT_PACKAGE
        return
        #else
        guard !Self.isRunningTests else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings()
        guard status.authorizationStatus == .authorized || status.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Transcript ready"
        content.subtitle = episode.podcastName ?? "Podcast"
        content.body = episode.title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "transcription-\(transcript.sourceEpisodeID)-\(transcript.generatedAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            logger.debug("Failed to deliver transcription notification: \(error.localizedDescription, privacy: .public)")
        }
        #endif
        #endif
    }

    /// Removes a temporary audio file that is no longer required.
    private func cleanupTemporaryFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            logger.debug("Removed temporary transcription file at \(url.path, privacy: .private)")
        } catch {
            logger.debug("Failed to remove temporary transcription file at \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Audio Preparation

struct PreparedAudio: Sendable {
    let url: URL
    let cleanupURLs: [URL]
    let duration: Double?
}

/// Converts/normalizes audio into a Speech-friendly format and ensures a local URL is available.
final class DefaultTranscriptionAudioPreparer: TranscriptionAudioPreparing, @unchecked Sendable {
    private let logger = AppLogger.transcription

    func prepareAudio(for url: URL, episodeID: String) async throws -> PreparedAudio {
        if url.isFileURL {
            return try await ensureSpeechCompatibleURL(for: url, episodeID: episodeID, cleanup: [])
        }

        let tempDirectory = FileManager.default.temporaryDirectory
        let filename = makeTemporaryFilename(for: episodeID, originalURL: url)
        let targetURL = tempDirectory.appendingPathComponent(filename)

        do {
            let (downloadURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: downloadURL, to: targetURL)
            return try await ensureSpeechCompatibleURL(for: targetURL, episodeID: episodeID, cleanup: [targetURL])
        } catch {
            throw EpisodeTranscriptionError.downloadFailed(underlying: error)
        }
    }

    private func makeTemporaryFilename(for episodeID: String, originalURL: URL, forcedExtension: String? = nil) -> String {
        let hashedID: String
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(episodeID.utf8))
        hashedID = digest.map { String(format: "%02x", $0) }.joined()
        #else
        hashedID = episodeID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        #endif

        let ext = forcedExtension ?? (originalURL.pathExtension.isEmpty ? "mp3" : originalURL.pathExtension)
        let basename = "transcription-\(hashedID)-\(UUID().uuidString)"
        return "\(basename).\(ext)"
    }

    private func ensureSpeechCompatibleURL(for url: URL, episodeID: String, cleanup: [URL]) async throws -> PreparedAudio {
        #if canImport(AVFoundation)
        let compatibleExtensions: Set<String> = ["caf", "wav", "aif", "aiff"]
        if compatibleExtensions.contains(url.pathExtension.lowercased()) {
            let asset = AVURLAsset(url: url)
            let durationTime = try? await asset.load(.duration)
            let duration = durationTime?.seconds
            return PreparedAudio(url: url, cleanupURLs: cleanup, duration: (duration?.isFinite == true) ? duration : nil)
        }

        let asset = AVURLAsset(url: url)
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw EpisodeTranscriptionError.audioPreparationFailed(
                underlying: error
            )
        }

        guard let track = audioTracks.first else {
            throw EpisodeTranscriptionError.audioPreparationFailed(
                underlying: NSError(
                    domain: "EpisodeTranscriptionManager",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "No audio track found in downloaded media."]
                )
            )
        }

        let outputFilename = makeTemporaryFilename(for: episodeID, originalURL: url, forcedExtension: "caf")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFilename)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(atPath: outputURL.path)
        }

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)
        } catch {
            throw EpisodeTranscriptionError.audioPreparationFailed(underlying: error)
        }

        let linearPCMSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: linearPCMSettings)
        guard reader.canAdd(readerOutput) else {
            throw EpisodeTranscriptionError.audioPreparationFailed(
                underlying: NSError(
                    domain: "EpisodeTranscriptionManager",
                    code: -1004,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to configure audio reader output."]
                )
            )
        }
        reader.add(readerOutput)

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: linearPCMSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw EpisodeTranscriptionError.audioPreparationFailed(
                underlying: NSError(
                    domain: "EpisodeTranscriptionManager",
                    code: -1005,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to configure audio writer input."]
                )
            )
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw EpisodeTranscriptionError.audioPreparationFailed(
                underlying: reader.error ?? NSError(
                    domain: "EpisodeTranscriptionManager",
                    code: -1006,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to begin reading audio."]
                )
            )
        }

        guard writer.startWriting() else {
            reader.cancelReading()
            throw EpisodeTranscriptionError.audioPreparationFailed(
                underlying: writer.error ?? NSError(
                    domain: "EpisodeTranscriptionManager",
                    code: -1007,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to begin writing audio."]
                )
            )
        }

        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = AudioConversionContext(
                reader: reader,
                writer: writer,
                readerOutput: readerOutput,
                writerInput: writerInput
            )
            context.start(continuation: continuation)
        }

        let durationTime = try? await asset.load(.duration)
        let duration = durationTime?.seconds
        logger.debug("Audio converted to speech-friendly PCM at \(outputURL.lastPathComponent, privacy: .public)")
        return PreparedAudio(url: outputURL, cleanupURLs: cleanup + [outputURL], duration: (duration?.isFinite == true) ? duration : nil)
        #else
        return PreparedAudio(url: url, cleanupURLs: cleanup, duration: nil)
        #endif
    }
}

#if canImport(AVFoundation)
private final class AudioConversionContext {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let readerOutput: AVAssetReaderTrackOutput
    private let writerInput: AVAssetWriterInput
    private let queue = DispatchQueue(label: "com.podrams.transcription.audioConversion")
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasFinished = false

    init(reader: AVAssetReader, writer: AVAssetWriter, readerOutput: AVAssetReaderTrackOutput, writerInput: AVAssetWriterInput) {
        self.reader = reader
        self.writer = writer
        self.readerOutput = readerOutput
        self.writerInput = writerInput
    }

    func start(continuation: CheckedContinuation<Void, Error>) {
        precondition(self.continuation == nil, "AudioConversionContext.start should only be invoked once.")
        self.continuation = continuation
        writerInput.requestMediaDataWhenReady(on: queue) { [self] in
            drainBuffers()
        }
    }

    private func drainBuffers() {
        guard continuation != nil, !hasFinished else { return }

        while writerInput.isReadyForMoreMediaData {
            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                if !writerInput.append(sampleBuffer) {
                    writerInput.markAsFinished()
                    let underlying = writer.error ?? NSError(
                        domain: "EpisodeTranscriptionManager",
                        code: -1008,
                        userInfo: [NSLocalizedDescriptionKey: "Failed while writing converted audio."]
                    )
                    fail(with: .audioPreparationFailed(underlying: underlying))
                    return
                }
            } else {
                writerInput.markAsFinished()
                finalizeWriting()
                return
            }
        }
    }

    private func finalizeWriting() {
        writer.finishWriting { [self] in
            if let error = writer.error {
                fail(with: .audioPreparationFailed(underlying: error))
            } else if writer.status == .completed {
                succeed()
            } else {
                let info = NSError(
                    domain: "EpisodeTranscriptionManager",
                    code: -1009,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected writer status \(writer.status.rawValue)."]
                )
                fail(with: .audioPreparationFailed(underlying: info))
            }
        }
    }

    private func succeed() {
        guard let continuation else { return }
        guard !hasFinished else { return }
        hasFinished = true
        self.continuation = nil
        continuation.resume(returning: ())
    }

    private func fail(with error: EpisodeTranscriptionError) {
        guard let continuation else { return }
        guard !hasFinished else { return }
        hasFinished = true
        self.continuation = nil
        reader.cancelReading()
        writer.cancelWriting()
        continuation.resume(throwing: error)
    }
}

extension AudioConversionContext: @unchecked Sendable {}
#endif

// MARK: - Transcript Cache

/// Disk + memory transcript cache so we avoid re-running expensive transcriptions.
final class DiskTranscriptCache: TranscriptCaching, @unchecked Sendable {
    private struct StoredTranscript: Codable {
        let text: String
        let generatedAt: Date
        let sourceEpisodeID: String
    }

    private let logger = AppLogger.transcription
    private let directory: URL
    private let fileManager = FileManager.default
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

    private var memoryCache: [String: EpisodeTranscriptionManager.Transcript] = [:]

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
            self.directory = caches.appendingPathComponent("Transcripts", isDirectory: true)
        }

        if !fileManager.fileExists(atPath: self.directory.path) {
            try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        }
    }

    func cachedTranscript(for episodeID: String) -> EpisodeTranscriptionManager.Transcript? {
        if let cached = memoryCache[episodeID] {
            return cached
        }

        let url = fileURL(for: episodeID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let stored = try decoder.decode(StoredTranscript.self, from: data)
            let transcript = EpisodeTranscriptionManager.Transcript(
                text: stored.text,
                generatedAt: stored.generatedAt,
                sourceEpisodeID: stored.sourceEpisodeID
            )
            memoryCache[episodeID] = transcript
            return transcript
        } catch {
            logger.debug("Failed to load cached transcript: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func store(_ transcript: EpisodeTranscriptionManager.Transcript, for episodeID: String) {
        memoryCache[episodeID] = transcript
        let url = fileURL(for: episodeID)
        let stored = StoredTranscript(
            text: transcript.text,
            generatedAt: transcript.generatedAt,
            sourceEpisodeID: transcript.sourceEpisodeID
        )
        do {
            let data = try encoder.encode(stored)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.debug("Failed to persist transcript to disk: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeCachedTranscript(for episodeID: String) {
        memoryCache.removeValue(forKey: episodeID)
        let url = fileURL(for: episodeID)
        try? fileManager.removeItem(at: url)
    }

    private func fileURL(for episodeID: String) -> URL {
        let hashedID: String
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(episodeID.utf8))
        hashedID = digest.map { String(format: "%02x", $0) }.joined()
        #else
        hashedID = episodeID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        #endif

        return directory.appendingPathComponent("\(hashedID).json")
    }
}

// MARK: - Speech Transcriber (Segmented)

/// Speech framework backed transcriber that streams the episode in short chunks to avoid server limits.
final class SegmentedSpeechTranscriber: EpisodeTranscribing, @unchecked Sendable {
    private let logger = AppLogger.transcription
    private let segmentDuration: TimeInterval
    private let chunkFrameCount: AVAudioFrameCount

    /// - Parameters:
    ///   - segmentDuration: Maximum duration of a single recognition request. SFSpeech recognizers struggle with long files; we stream ~1 minute chunks.
    ///   - chunkFrameCount: Number of frames pushed per buffer append.
    init(segmentDuration: TimeInterval = 55, chunkFrameCount: AVAudioFrameCount = 32_000) {
        self.segmentDuration = segmentDuration
        self.chunkFrameCount = chunkFrameCount
    }

    func transcribe(preparedAudio: PreparedAudio, metadata: EpisodeTranscriptionMetadata) async throws -> String {
        #if canImport(Speech)
        #if canImport(AVFoundation)
        try await ensureAuthorization()

        let recognizer = try makeRecognizer()
        guard recognizer.isAvailable else {
            throw EpisodeTranscriptionError.frameworkUnavailable
        }

        let segmenter = try AudioSegmenter(
            fileURL: preparedAudio.url,
            segmentDuration: segmentDuration,
            chunkFrameCount: chunkFrameCount
        )

        var segments: [String] = []

        while let buffers = try segmenter.nextSegmentBuffers() {
            try Task.checkCancellation()
            guard !buffers.isEmpty else { continue }
            let piece = try await transcribeSegment(
                buffers: buffers,
                recognizer: recognizer,
                metadata: metadata
            )
            if !piece.isEmpty {
                segments.append(piece)
            }
        }

        let combined = segments.joined(separator: "\n\n")
        return combined
        #else
        throw EpisodeTranscriptionError.unsupportedPlatform
        #endif
        #else
        throw EpisodeTranscriptionError.unsupportedPlatform
        #endif
    }

    private func ensureAuthorization() async throws {
        #if canImport(Speech)
        let status = await SegmentedSpeechTranscriber.requestAuthorization()
        switch status {
        case .authorized:
            return
        case .denied, .restricted, .notDetermined:
            throw EpisodeTranscriptionError.authorizationDenied
        @unknown default:
            throw EpisodeTranscriptionError.authorizationDenied
        }
        #else
        throw EpisodeTranscriptionError.frameworkUnavailable
        #endif
    }

    private func makeRecognizer() throws -> SFSpeechRecognizer {
        #if canImport(Speech)
        if let localeRecognizer = SFSpeechRecognizer(locale: Locale.current) {
            return localeRecognizer
        }
        if let fallback = SFSpeechRecognizer(locale: Locale(identifier: "en_US")) {
            return fallback
        }
        throw EpisodeTranscriptionError.noRecognizer
        #else
        throw EpisodeTranscriptionError.frameworkUnavailable
        #endif
    }

    private func transcribeSegment(
        buffers: [AVAudioPCMBuffer],
        recognizer: SFSpeechRecognizer,
        metadata: EpisodeTranscriptionMetadata
    ) async throws -> String {
        #if canImport(Speech)
        let contextualStrings = [metadata.episodeTitle, metadata.podcastTitle].compactMap { $0 }

        try Task.checkCancellation()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.taskHint = .dictation
            request.contextualStrings = contextualStrings

            var didFinish = false
            var recognitionTask: SFSpeechRecognitionTask?

            func finish(_ result: Result<String, EpisodeTranscriptionError>) {
                guard !didFinish else { return }
                didFinish = true
                recognitionTask?.cancel()
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    finish(.failure(.underlying(error)))
                    return
                }

                guard let result else { return }

                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    finish(.success(trimmed))
                }
            }

            for buffer in buffers {
                request.append(buffer)
            }
            request.endAudio()

            if Task.isCancelled {
                finish(.failure(.cancelled))
            }
        }
        #else
        throw EpisodeTranscriptionError.frameworkUnavailable
        #endif
    }

    #if canImport(Speech)
    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    #endif
}

// MARK: - Speech Analyzer Transcriber (Modern)

@available(macOS 26.0, iOS 26.0, *)
final class SpeechAnalyzerTranscriber: EpisodeTranscribing, @unchecked Sendable {
    static var isSupported: Bool {
        #if canImport(Speech)
        return true
        #else
        return false
        #endif
    }

    private let logger = AppLogger.transcription
    private let preset: SpeechTranscriber.Preset = .timeIndexedProgressiveTranscription

    func transcribe(preparedAudio: PreparedAudio, metadata: EpisodeTranscriptionMetadata) async throws -> String {
        #if canImport(Speech)
        guard SpeechTranscriber.isAvailable else {
            throw EpisodeTranscriptionError.frameworkUnavailable
        }

        let candidates = await localeCandidates()
        guard !candidates.isEmpty else {
            throw EpisodeTranscriptionError.noRecognizer
        }

        var lastError: Error?

        for candidate in candidates {
            do {
                return try await withTimeout(seconds: 180) { [self] in
                    try await self.transcribeWithAnalyzer(
                        preparedAudio: preparedAudio,
                        metadata: metadata,
                        candidate: candidate
                    )
                }
            } catch {
                lastError = error
                logger.debug("SpeechAnalyzer candidate \(candidate.locale.identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public); trying next if available.")
            }
        }

        throw lastError ?? EpisodeTranscriptionError.noRecognizer
        #else
        throw EpisodeTranscriptionError.frameworkUnavailable
        #endif
    }

    /// Picks a locale that is installed (preferred) or supported for the current environment.
    private func matchLocale(in locales: [Locale]) -> Locale? {
        let targets = [
            Locale.current,
            Locale(identifier: "en_US")
        ]

        for target in targets {
            if let exact = locales.first(where: { $0.identifier == target.identifier }) {
                return exact
            }
            if let languageMatch = locales.first(where: { languageIdentifier(for: $0) == languageIdentifier(for: target) }) {
                return languageMatch
            }
        }
        return nil
    }

    private func languageIdentifier(for locale: Locale) -> String? {
        locale.language.languageCode?.identifier
    }

    private func localeCandidates() async -> [LocaleCandidate] {
        let installedLocales = await SpeechTranscriber.installedLocales
        var candidates: [LocaleCandidate] = []

        if let installed = matchLocale(in: installedLocales) {
            candidates.append(.init(locale: installed, isInstalled: true))
            logger.debug("Using installed SpeechTranscriber locale \(installed.identifier, privacy: .public)")
        }

        let supportedPrimary = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        let supportedFallback = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))

        for locale in [supportedPrimary, supportedFallback].compactMap({ $0 }) {
            if candidates.contains(where: { $0.locale.identifier == locale.identifier }) { continue }
            let isInstalled = installedLocales.contains(where: { $0.identifier == locale.identifier })
            candidates.append(.init(locale: locale, isInstalled: isInstalled))
            logger.debug("Using supported SpeechTranscriber locale \(locale.identifier, privacy: .public); installed=\(isInstalled, privacy: .public)")
        }

        if candidates.isEmpty {
            logger.error("No supported SpeechTranscriber locale could be resolved")
        }

        return candidates
    }

    private func collectResults(from transcriber: SpeechTranscriber) -> Task<[String], Error> {
        Task {
            var segments: [String] = []
            for try await result in transcriber.results {
                guard result.isFinal else {
                    continue
                }
                let text = normalizeTranscript(String(result.text.characters))
                if !text.isEmpty {
                    segments.append(text)
                }
            }
            return segments
        }
    }

    /// Collapses eager line breaks from streaming results while preserving double-newline paragraph gaps.
    private func normalizeTranscript(_ text: String) -> String {
        var output: [Character] = []
        output.reserveCapacity(text.count)

        var newlineRun = 0
        var previousWasSpace = false

        func flushNewlines() {
            if newlineRun >= 2 {
                if !output.isEmpty && output.last != "\n" {
                    output.append("\n")
                }
                output.append("\n")
                previousWasSpace = false
            } else if newlineRun == 1 {
                if !previousWasSpace {
                    output.append(" ")
                    previousWasSpace = true
                }
            }
            newlineRun = 0
        }

        for scalar in text.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) || scalar == "\u{2028}" || scalar == "\u{2029}" {
                newlineRun += 1
                continue
            }

            flushNewlines()

            if CharacterSet.whitespaces.contains(scalar) {
                if !previousWasSpace {
                    output.append(" ")
                    previousWasSpace = true
                }
                continue
            }

            previousWasSpace = false
            output.append(Character(scalar))
        }

        flushNewlines()

        // Collapse any residual double spaces that may have slipped through.
        var collapsed: [Character] = []
        collapsed.reserveCapacity(output.count)
        var lastWasSpace = false
        for ch in output {
            if ch == " " {
                if lastWasSpace { continue }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
            collapsed.append(ch)
        }

        // Trim leading/trailing spaces and newlines.
        let normalized = String(collapsed).trimmingCharacters(in: .whitespacesAndNewlines)

        // Insert line breaks after sentence-ending punctuation while preserving existing paragraph breaks.
        let paragraphPlaceholder = "\u{0007}"
        var working = normalized.replacingOccurrences(of: "\n\n", with: paragraphPlaceholder)
        working = working.replacingOccurrences(of: "([.!?])\\s+", with: "$1\n", options: .regularExpression)
        working = working.replacingOccurrences(of: paragraphPlaceholder, with: "\n\n")
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcribeWithAnalyzer(
        preparedAudio: PreparedAudio,
        metadata: EpisodeTranscriptionMetadata,
        candidate: LocaleCandidate
    ) async throws -> String {
        try await AssetInventory.reserve(locale: candidate.locale)
        defer { Task { await AssetInventory.release(reservedLocale: candidate.locale) } }

        let transcriber = SpeechTranscriber(
            locale: candidate.locale,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: preset.reportingOptions.union([.alternativeTranscriptions]),
            attributeOptions: preset.attributeOptions.union([.transcriptionConfidence])
        )

        if candidate.isInstalled == false {
            guard let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw EpisodeTranscriptionError.downloadFailed(
                    underlying: NSError(
                        domain: "SpeechAnalyzer",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "No asset installation request returned for locale \(candidate.locale.identifier)."]
                    )
                )
            }
            try await request.downloadAndInstall()

            let refreshed = await SpeechTranscriber.installedLocales
            guard refreshed.contains(where: { $0.identifier == candidate.locale.identifier }) else {
                throw EpisodeTranscriptionError.downloadFailed(
                    underlying: NSError(
                        domain: "SpeechAnalyzer",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Transcription assets could not be installed for locale \(candidate.locale.identifier)."]
                    )
                )
            }
        }

        let audioFile = try AVAudioFile(forReading: preparedAudio.url)

        let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? audioFile.processingFormat
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)
        try await analyzer.prepareToAnalyze(in: bestFormat, withProgressReadyHandler: nil)

        let context = AnalysisContext()
        context.contextualStrings[AnalysisContext.ContextualStringsTag("podcastTitle")] = [metadata.podcastTitle ?? ""]
        context.contextualStrings[AnalysisContext.ContextualStringsTag("episodeTitle")] = [metadata.episodeTitle]
        try? await analyzer.setContext(context)

        let resultsTask = collectResults(from: transcriber)
        defer { resultsTask.cancel() }

        let transcription = try await withTaskCancellationHandler {
            let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile)
            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            let segments = try await resultsTask.value
            let combined = segments.joined(separator: " ")
            let normalizedCombined = normalizeTranscript(combined)
            guard !normalizedCombined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EpisodeTranscriptionError.emptyResult
            }
            return normalizedCombined
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }

        return transcription
    }
}

@available(macOS 26.0, iOS 26.0, *)
private struct LocaleCandidate {
    let locale: Locale
    let isInstalled: Bool
}

@available(macOS 26.0, iOS 26.0, *)
private enum TimeoutError: Error, Sendable {
    case timedOut
}

@available(macOS 26.0, iOS 26.0, *)
private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut
        }

        if let result = try await group.next() {
            group.cancelAll()
            return result
        }

        group.cancelAll()
        throw TimeoutError.timedOut
    }
}

// MARK: - Audio Segmentation

/// Reads audio from disk and returns speech-sized buffer groups.
private final class AudioSegmenter {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let segmentFrameLimit: AVAudioFrameCount
    private let chunkFrameCount: AVAudioFrameCount

    init(fileURL: URL, segmentDuration: TimeInterval, chunkFrameCount: AVAudioFrameCount) throws {
        guard segmentDuration > 0 else { throw EpisodeTranscriptionError.segmentationFailed }
        guard chunkFrameCount > 0 else { throw EpisodeTranscriptionError.segmentationFailed }

        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw EpisodeTranscriptionError.audioPreparationFailed(underlying: error)
        }

        format = file.processingFormat
        let framesPerSegment = AVAudioFrameCount(segmentDuration * format.sampleRate)
        segmentFrameLimit = max(framesPerSegment, chunkFrameCount)
        self.chunkFrameCount = chunkFrameCount
    }

    func nextSegmentBuffers() throws -> [AVAudioPCMBuffer]? {
        if file.framePosition >= file.length {
            return nil
        }

        var remaining = segmentFrameLimit
        var buffers: [AVAudioPCMBuffer] = []

        while remaining > 0 {
            let frameCount = min(remaining, chunkFrameCount)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw EpisodeTranscriptionError.segmentationFailed
            }

            do {
                try file.read(into: buffer, frameCount: frameCount)
            } catch {
                throw EpisodeTranscriptionError.audioPreparationFailed(underlying: error)
            }

            if buffer.frameLength == 0 {
                break
            }

            buffers.append(buffer)
            remaining -= buffer.frameLength

            if file.framePosition >= file.length {
                break
            }
        }

        return buffers.isEmpty ? nil : buffers
    }
}
