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
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Transcription requires macOS with Tahoe Speech Transcriber support."
        case .authorizationDenied:
            return "Speech recognition permission was not granted."
        case .frameworkUnavailable:
            return "Tahoe Speech Transcriber is not available on this system."
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
    func transcribeAudio(at url: URL, metadata: EpisodeTranscriptionMetadata) async throws -> String
}

/// Actor responsible for coordinating episode transcription, caching the results, and preparing audio files.
actor EpisodeTranscriptionManager {
    static let shared = EpisodeTranscriptionManager()

    struct Transcript: Sendable {
        let text: String
        let generatedAt: Date
        let sourceEpisodeID: String
    }

    private let logger = AppLogger.transcription
    private var cache: [String: Transcript] = [:]
    private var inFlightTasks: [String: Task<Transcript, Error>] = [:]

    /// Returns a cached transcript if one exists.
    func cachedTranscript(for episode: PodcastEpisode) -> Transcript? {
        cache[episode.id]
    }

    /// Returns a transcript for the given episode, kicking off transcription if necessary.
    func transcript(for episode: PodcastEpisode) async throws -> Transcript {
        if let cached = cache[episode.id] {
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
        defer {
            inFlightTasks.removeValue(forKey: episode.id)
        }

        do {
            let transcript = try await task.value
            cache[episode.id] = transcript
            return transcript
        } catch {
            logger.error("Transcription failed for episode \(episode.title, privacy: .private): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Performs the transcription work, preparing the audio file and invoking the Tahoe (or fallback) engine.
    private func performTranscription(for episode: PodcastEpisode) async throws -> Transcript {
        logger.info("Starting transcription for episode \(episode.title, privacy: .private)")

        // Obtain the best URL for the episode (preferring local downloads).
        let playbackURL = await MainActor.run {
            DownloadManager.shared.playbackURL(for: episode)
        }

        // Ensure we have a file URL available for the transcription engine.
        let urlPreparation = try await prepareLocalAudioURL(from: playbackURL, episodeID: episode.id)
        defer {
            for url in urlPreparation.cleanupURLs {
                cleanupTemporaryFile(at: url)
            }
        }

        let metadata = EpisodeTranscriptionMetadata(
            episodeTitle: episode.title,
            podcastTitle: episode.podcastName ?? episode.feedUrl,
            duration: episode.duration
        )

        do {
            if #available(macOS 26.0, *), let modernTranscript = try await transcribeWithSpeechAnalyzer(at: urlPreparation.url, metadata: metadata) {
                let normalized = modernTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw EpisodeTranscriptionError.emptyResult
                }
                logger.info("Completed transcription via SpeechAnalyzer for episode \(episode.title, privacy: .private)")
                return Transcript(text: normalized, generatedAt: Date(), sourceEpisodeID: episode.id)
            }

            let text = try await TahoeTranscriberFacade.shared.transcribeAudio(at: urlPreparation.url, metadata: metadata)
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw EpisodeTranscriptionError.emptyResult
            }
            logger.info("Completed transcription for episode \(episode.title, privacy: .private)")
            let transcript = Transcript(text: normalized, generatedAt: Date(), sourceEpisodeID: episode.id)

            return transcript
        } catch is CancellationError {
            throw EpisodeTranscriptionError.cancelled
        } catch let error as EpisodeTranscriptionError {
            throw error
        } catch {
            throw EpisodeTranscriptionError.underlying(error)
        }
    }

    private struct LocalAudioPreparation {
        let url: URL
        let cleanupURLs: [URL]
    }

    /// Ensures the audio is available as a local file URL for transcription engines that require disk access.
    private func prepareLocalAudioURL(from url: URL, episodeID: String) async throws -> LocalAudioPreparation {
        if url.isFileURL {
            return try await ensureSpeechCompatibleURL(for: url, episodeID: episodeID, cleanup: [])
        }

        // Download remote audio to a temporary location for transcription.
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

    private func ensureSpeechCompatibleURL(for url: URL, episodeID: String, cleanup: [URL]) async throws -> LocalAudioPreparation {
        #if canImport(AVFoundation)
        let compatibleExtensions: Set<String> = ["caf", "wav", "aif", "aiff"]
        if compatibleExtensions.contains(url.pathExtension.lowercased()) {
            return LocalAudioPreparation(url: url, cleanupURLs: cleanup)
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

        logger.debug("Audio converted to speech-friendly PCM at \(outputURL.lastPathComponent, privacy: .public)")
        return LocalAudioPreparation(url: outputURL, cleanupURLs: cleanup + [outputURL])
        #else
        return LocalAudioPreparation(url: url, cleanupURLs: cleanup)
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

#if canImport(AVFoundation)
@available(macOS 26.0, *)
private extension EpisodeTranscriptionManager {
    func transcribeWithSpeechAnalyzer(at url: URL, metadata: EpisodeTranscriptionMetadata) async throws -> String? {
        #if compiler(>=6.2)
        guard SpeechTranscriber.isAvailable else {
            logger.warning("SpeechAnalyzer: SpeechTranscriber unavailable on this system")
            return nil
        }

        let requestedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        let locale = requestedLocale ?? Locale(identifier: "en_US")

        try await AssetInventory.reserve(locale: locale)
        defer {
            Task {
                await AssetInventory.release(reservedLocale: locale)
            }
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let modules: [any Speech.SpeechModule] = [transcriber]

        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            logger.debug("SpeechAnalyzer: Installing assets for locale \(locale.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: modules)
        let audioFile = try AVAudioFile(forReading: url)

        let resultsTask = Task.detached(priority: .utility) { () -> AttributedString in
            var combined = AttributedString()
            for try await result in transcriber.results {
                combined += result.text
            }
            return combined
        }

        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            let attributed = try await resultsTask.value
            return String(attributed.characters)
        } catch {
            resultsTask.cancel()
            throw error
        }
        #else
        return nil
        #endif
    }
}
#endif

// MARK: - Tahoe Transcriber Facade

/// Facade that prefers the Tahoe Speech Transcriber API and falls back to the Speech framework when necessary.
final class TahoeTranscriberFacade: Sendable {
    static let shared = TahoeTranscriberFacade()

    private let logger = AppLogger.transcription
    private let backend: EpisodeTranscribing

    init() {
        if #available(macOS 15.0, *), let tahoe = TahoeSpeechTranscriberAdapter() {
            logger.debug("Using Tahoe Speech Transcriber backend.")
            backend = tahoe
        } else {
            logger.debug("Tahoe Speech Transcriber unavailable; falling back to Speech recognizer backend.")
            backend = SpeechFrameworkTranscriber()
        }
    }

    func transcribeAudio(at url: URL, metadata: EpisodeTranscriptionMetadata) async throws -> String {
        try await backend.transcribeAudio(at: url, metadata: metadata)
    }
}

// MARK: - Tahoe Speech Transcriber Adapter

@available(macOS 15.0, *)
final class TahoeSpeechTranscriberAdapter: EpisodeTranscribing, @unchecked Sendable {

    private let logger = AppLogger.transcription
    private let transcriberInstance: AnyObject?

    init?() {
        // Attempt to dynamically resolve the Tahoe Speech Transcriber class from the new framework.
        guard let clazz = NSClassFromString("TahoeSpeechTranscriber") as? NSObject.Type else {
            return nil
        }
        transcriberInstance = clazz.init()
    }

    func transcribeAudio(at url: URL, metadata: EpisodeTranscriptionMetadata) async throws -> String {
        guard let transcriberInstance else {
            throw EpisodeTranscriptionError.frameworkUnavailable
        }

        // The WWDC 2025 session introduces async Tahoe APIs. We attempt to invoke them dynamically in order
        // to keep backward compatibility when compiling against older SDKs where the symbols may not exist.
        let selector = NSSelectorFromString("transcribeAudioAtURL:configuration:")
        if transcriberInstance.responds(to: selector) {
            return try await invokeAsyncTranscription(on: transcriberInstance, selector: selector, url: url, metadata: metadata)
        }

        let simplifiedSelector = NSSelectorFromString("transcribeAudioAtURL:")
        if transcriberInstance.responds(to: simplifiedSelector) {
            return try await invokeAsyncTranscription(on: transcriberInstance, selector: simplifiedSelector, url: url, metadata: metadata)
        }

        logger.error("TahoeSpeechTranscriber instance does not respond to expected selectors.")
        throw EpisodeTranscriptionError.frameworkUnavailable
    }

    private func invokeAsyncTranscription(on object: AnyObject, selector: Selector, url: URL, metadata: EpisodeTranscriptionMetadata) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var configuration: AnyObject?
            if selector == NSSelectorFromString("transcribeAudioAtURL:configuration:") {
                configuration = configurationObject(from: metadata)
            }

            let completionSelector = NSSelectorFromString("transcribeAudioAtURL:completionHandler:")
            if object.responds(to: completionSelector) {
                // Prefer an API that takes a completion handler if it exists.
                let invocationSelector = completionSelector
                let completionBlock: @convention(block) (AnyObject?, Error?) -> Void = { result, error in
                    if let error {
                        continuation.resume(throwing: EpisodeTranscriptionError.underlying(error))
                        return
                    }
                    if let result = result, let transcript = result.value(forKey: "text") as? String {
                        continuation.resume(returning: transcript)
                    } else {
                        continuation.resume(throwing: EpisodeTranscriptionError.emptyResult)
                    }
                }
                let blockObject: AnyObject = completionBlock as AnyObject
                _ = object.perform(invocationSelector, with: url as NSURL, with: blockObject)
                return
            }

            // Otherwise try invoking an async method and assume it returns a result synchronously.
            let response = object.perform(selector, with: url as NSURL, with: configuration)
            if let result = response?.takeUnretainedValue(), let transcript = result.value(forKey: "text") as? String {
                continuation.resume(returning: transcript)
            } else {
                continuation.resume(throwing: EpisodeTranscriptionError.emptyResult)
            }
        }
    }

    private func configurationObject(from metadata: EpisodeTranscriptionMetadata) -> AnyObject? {
        guard let clazz = NSClassFromString("TahoeSpeechTranscriberConfiguration") as? NSObject.Type else {
            return nil
        }
        let config = clazz.init()
        config.setValue(metadata.episodeTitle, forKey: "displayName")
        if let podcast = metadata.podcastTitle {
            config.setValue(podcast, forKey: "containerDisplayName")
        }
        if let duration = metadata.duration {
            config.setValue(duration, forKey: "duration")
        }
        return config
    }
}

// MARK: - Speech Framework Fallback

/// Fallback implementation that uses `SFSpeechRecognizer` when Tahoe is unavailable.
private final class SpeechFrameworkTranscriber: EpisodeTranscribing {

    private let logger = AppLogger.transcription

    func transcribeAudio(at url: URL, metadata: EpisodeTranscriptionMetadata) async throws -> String {
        #if canImport(Speech)
        try await ensureAuthorization()

        guard let recognizer = SFSpeechRecognizer() else {
            throw EpisodeTranscriptionError.noRecognizer
        }

        if !recognizer.isAvailable {
            throw EpisodeTranscriptionError.frameworkUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = false
            request.shouldReportPartialResults = false

            var hasResumed = false
            let recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error {
                    hasResumed = true
                    continuation.resume(throwing: EpisodeTranscriptionError.underlying(error))
                    return
                }

                guard let result else {
                    return
                }

                if result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
            
            _ = recognitionTask
        }
        #else
        throw EpisodeTranscriptionError.frameworkUnavailable
        #endif
    }

    private func ensureAuthorization() async throws {
        #if canImport(Speech)
        let status = await SpeechFrameworkTranscriber.requestAuthorization()
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw EpisodeTranscriptionError.authorizationDenied
        case .notDetermined:
            throw EpisodeTranscriptionError.authorizationDenied
        @unknown default:
            throw EpisodeTranscriptionError.authorizationDenied
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
