import Foundation
import AppIntents
import OSLog

private let shortcutLogger = AppLogger.shortcuts

@available(macOS 15, *)
struct TogglePlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = .init("Shortcuts.TogglePlayback.Title", table: "Localizable")
    static let description = IntentDescription(.init("Shortcuts.TogglePlayback.Description", table: "Localizable"))
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        let outcome = await ShortcutPlaybackController.shared.togglePlayback()
        return .result(dialog: outcome.dialog)
    }
}

@available(macOS 15, *)
struct PlayLastEpisodeIntent: AppIntent {
    static let title: LocalizedStringResource = .init("Shortcuts.PlayLast.Title", table: "Localizable")
    static let description = IntentDescription(.init("Shortcuts.PlayLast.Description", table: "Localizable"))
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        let outcome = await ShortcutPlaybackController.shared.playLastSavedEpisode()
        return .result(dialog: outcome.dialog)
    }
}

@available(macOS 15, *)
struct PodRamsShortcuts: AppShortcutsProvider {
    static var appShortcutsTitle: LocalizedStringResource { .init("Shortcuts.AppShortcutsTitle", table: "Localizable") }
    static var shortcutTileColor: ShortcutTileColor { .blue }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TogglePlaybackIntent(),
            phrases: [
                "\(.applicationName) toggle playback",
                "Pause \(.applicationName)",
                "Play in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcuts.TogglePlayback.Title", table: "Localizable"),
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: PlayLastEpisodeIntent(),
            phrases: [
                "Resume in \(.applicationName)",
                "Play last episode in \(.applicationName)",
                "Keep listening with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcuts.PlayLast.Title", table: "Localizable"),
            systemImageName: "gobackward"
        )
    }
}

@available(macOS 15, *)
struct ShortcutPlaybackOutcome {
    enum State {
        case playing
        case paused
        case idle
    }

    let state: State
    let message: String

    var dialog: IntentDialog {
        IntentDialog(stringLiteral: message)
    }
}

@available(macOS 15, *)
@MainActor
final class ShortcutPlaybackController {
    static let shared = ShortcutPlaybackController(
        audioController: AudioPlayer.shared,
        persistence: ShortcutPersistence()
    )

    private let audioController: ShortcutAudioControlling
    private let persistence: ShortcutPersisting

    init(audioController: ShortcutAudioControlling, persistence: ShortcutPersisting) {
        self.audioController = audioController
        self.persistence = persistence
    }

    func togglePlayback() async -> ShortcutPlaybackOutcome {
        if audioController.isPlaying {
            audioController.pauseAudio()
            shortcutLogger.info("Shortcut paused playback")
            return ShortcutPlaybackOutcome(state: .paused, message: ShortcutStrings.paused())
        }

        if let episode = audioController.currentEpisode {
            audioController.playEpisode(episode)
            persistLastPlaybackIfPossible(episode)
            shortcutLogger.info("Shortcut replaying current episode: \(episode.title, privacy: .private)")
            return ShortcutPlaybackOutcome(state: .playing, message: ShortcutStrings.playingEpisode(episode.title))
        }

        return await playLastSavedEpisode()
    }

    func playLastSavedEpisode() async -> ShortcutPlaybackOutcome {
        guard let episode = await persistence.loadLastPlayback() else {
            shortcutLogger.warning("Shortcut requested last episode but nothing was persisted")
            return ShortcutPlaybackOutcome(state: .idle, message: ShortcutStrings.nothingToPlay())
        }

        audioController.playEpisode(episode)
        persistLastPlaybackIfPossible(episode)
        shortcutLogger.info("Shortcut resumed saved episode: \(episode.title, privacy: .private)")
        return ShortcutPlaybackOutcome(state: .playing, message: ShortcutStrings.resumingEpisode(episode.title))
    }

    private func persistLastPlaybackIfPossible(_ episode: PodcastEpisode) {
        guard let feedUrl = episode.feedUrl, !feedUrl.isEmpty else { return }
        persistence.saveLastPlayback(episode: episode, feedUrl: feedUrl)
    }
}

protocol ShortcutPersisting {
    @MainActor
    func loadLastPlayback() async -> PodcastEpisode?
    @MainActor
    func saveLastPlayback(episode: PodcastEpisode, feedUrl: String?)
}

struct ShortcutPersistence: ShortcutPersisting {
    @MainActor
    func loadLastPlayback() async -> PodcastEpisode? {
        await PersistenceManager.loadLastPlayback()
    }

    @MainActor
    func saveLastPlayback(episode: PodcastEpisode, feedUrl: String?) {
        PersistenceManager.saveLastPlayback(episode: episode, feedUrl: feedUrl)
    }
}

@MainActor
protocol ShortcutAudioControlling: AnyObject {
    var isPlaying: Bool { get }
    var currentEpisode: PodcastEpisode? { get }

    func playEpisode(_ episode: PodcastEpisode)
    func pauseAudio()
}

extension AudioPlayer: ShortcutAudioControlling {}

enum ShortcutStrings {
    static func paused() -> String {
        plain("Shortcuts.Paused")
    }

    static func nothingToPlay() -> String {
        plain("Shortcuts.NothingToPlay")
    }

    static func playingEpisode(_ title: String) -> String {
        formatted("Shortcuts.PlayingEpisode.Format", title)
    }

    static func resumingEpisode(_ title: String) -> String {
        formatted("Shortcuts.ResumingEpisode.Format", title)
    }

    private static func plain(_ key: String) -> String {
        NSLocalizedString(key, comment: "Apple Shortcuts copy")
    }

    private static func formatted(_ key: String, _ title: String) -> String {
        let format = NSLocalizedString(key, comment: "Apple Shortcuts copy")
        return String(format: format, title)
    }
}
