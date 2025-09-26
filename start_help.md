# Start Help

## Build
- macOS: `open PodRams.xcodeproj` then build/run from Xcode (Debug scheme, Swift 6).
- CLI: `xcodebuild -project PodRams.xcodeproj -scheme PodRams -configuration Debug build` (ensure latest Xcode toolchain).
- SwiftPM utilities: `swift build` (outside sandbox) from repo root after trusting Package.swift.

## Swift Files Overview
- `PodRams/AppTheme.swift` — Central color/font palette. Features: auto dark/light adaptation, Liquid Glass tint presets.
- `PodRams/AppTests.swift` — High-level integration tests covering persistence, downloads. Features: validates init flows, guardrails.
- `PodRams/AudioOutputManager.swift` — Manages output routes, AirPlay icons, cache. Features: monitors system routes, publishes icon state.
- `PodRams/AudioOutputSelectionView.swift` — SwiftUI popover for selecting audio outputs. Features: lists routes, triggers manager switches.
- `PodRams/AudioPlayer.swift` — Core playback engine combining `AVPlayer` + `AVAudioEngine`. Features: streaming/local playback, pan/volume, observer cleanup.
- `PodRams/AudioPlayerOptimizations.swift` — Specialized helpers to tune CPU usage for player. Features: thread tuning, buffer sizing.
- `PodRams/CachedAsyncImage.swift` — Async image loader with caching + placeholders. Features: memory-aware cache, fade transitions.
- `PodRams/ConfiguredEpisodeRow.swift` — Wrapper supplying callbacks to `EpisodeRow`. Features: binds selection, seek, download triggers.
- `PodRams/ContentView.swift` — Root app shell orchestrating state, layout, popovers. Features: restoration, cue handling, toolbar, Liquid Glass composition.
- `PodRams/CueSheetView.swift` — Cue (queue) management UI. Features: drag reorder, bulk download, persistence sync.
- `PodRams/DebugMenu.swift` — Developer diagnostics menu. Features: inject test episodes, run health checks.
- `PodRams/DownloadButton.swift` — Styled control for initiating downloads. Features: progress indicator states.
- `PodRams/DownloadManager.swift` — Download lifecycle orchestrator. Features: resume/pause, file hashing, disk cache, playback URL helper.
- `PodRams/EqualizerBackdrop.swift` — Decorative animated equalizer background. Features: respects performance throttles.
- `PodRams/EpisodeListView.swift` — Scrollable episode list. Features: selection, download menu, cue toggles, playback via local-first URL.
- `PodRams/EpisodeRowBackground.swift` — Visual background styling for rows. Features: Liquid Glass shading.
- `PodRams/EpisodeRow_Previews.swift` — SwiftUI previews for rows. Features: sample data for design tuning.
- `PodRams/FavoritesView.swift` — Favorites browser popover. Features: lazy load episodes, offline-first play, list management.
- `PodRams/FeedKitRSSParser.swift` — Wrapper over FeedKit to parse RSS feeds. Features: optimized parsing, caching hints.
- `PodRams/ZMarkupParser.swift` — Markdown/HTML renderer for show notes. Features: themed typography, list markers, caching.
- `PodRams/FlowLayout.swift` — Custom layout helper. Features: adaptive grid flow respecting performance budgets.
- `PodRams/GlassBadgeView.swift` — Reusable badge with Liquid Glass effect. Features: animated counters, icon/text pairing.
- `PodRams/HelpCommands.swift` — Command menu content for help. Features: localized keyboard shortcut messaging.
- `PodRams/HoverableDownloadIndicator.swift` — Download progress hover control. Features: pause/resume, animations.
- `PodRams/HTMLStrippedString.swift` — Helpers to strip/sanitize HTML. Features: cached stripping, newline preservation.
- `PodRams/KeyboardShortcutView.swift` — Captures global shortcuts. Features: closure-based key routing.
- `PodRams/LiquidGlassCompatibility.swift` — Abstractions for Liquid Glass modifiers. Features: conditional modifiers per platform.
- `PodRams/LoadingIndicator.swift` — Reusable progress spinner. Features: style consistent with theme.
- `PodRams/MemoryOptimizations.swift` — Memory minimization utilities. Features: heuristics for trimming caches.
- `PodRams/Modles.swift` — Data models (`Podcast`, `PodcastEpisode`). Features: Codable support, estimated footprint.
- `PodRams/PlayCommands.swift` — Menu bar play controls. Features: local-first playback, navigation, volume.
- `PodRams/PlayedEpisodesManager.swift` — Tracks played history. Features: persistence, query helpers.
- `PodRams/PlayerView.swift` — Main player card UI. Features: artwork/show notes flip, controls, timers.
- `PodRams/PodcastFetcher.swift` — Fetches podcasts + episodes. Features: concurrency, artwork caching, prefetch.
- `PodRams/PodRamsApp.swift` — App entry point. Features: state bootstrapping, window configuration.
- `PodRams/PersistenceManager.swift` — Handles saving/loading favorites, cue, last playback. Features: disk IO batching, background tasks.
- `PodRams/PreviewSupport.swift` — Helpers for SwiftUI previews. Features: mock data, theme injection.
- `PodRams/ProgressBarView.swift` — Playback progress UI. Features: scrubbing, timer formatting.
- `PodRams/SearchSheetView.swift` — Podcast search UI. Features: result list, auto-play first episode (local-first).
- `PodRams/SettingsView.swift` — Settings popover. Features: toggles for cache, theme previews.
- `PodRams/SimpleEpisodeRow.swift` — Lightweight row variant. Features: quick actions, minimal effects.
- `PodRams/SubscribeView.swift` — Manage subscriptions. Features: load feeds, continue last playback, per-episode actions.
- `PodRams/Untitled.swift` — Scratch utilities (confirm usage before shipping). Features: experimental prototypes.

### Tests & Supporting Targets
- `PodRamsTests/DownloadManagerTests.swift` — Unit tests for download persistence and state.
- `PodRamsTests/PlayCommandsTests.swift` — Verifies command behaviors, playback toggles.
- `PodRamsTests/HelpCommandsTests.swift` — Validates localized help content.
- `PodRamsTests/ZMarkupParserTests.swift` — Exercises markup rendering for show notes (lists, emphasis, block quotes).
- `PodRamsUITests/...` — UI automation stubs (expand as needed).
- `PodRamsTests2/BasicTests.swift` — Smoke tests for audio player properties.
- `Tests/TestFeedKit.swift` & `FeedKit/*` — Vendor feed parsing tests/utilities.

- 2025-03-09 — Settings window adds 2× playback option with pitch-safe audio rate handling; Subscriptions, Favorites, Settings, and Output popovers restyled with Liquid Glass containers and theme-aware colors/icons.
- 2025-03-09 — Search sheet view adopts AppTheme colors for light/dark consistency (background, text, icons).
- 2025-03-09 — Search/Subscribed selections repopulate episodes correctly after playback so navigation stays intact.
- 2025-03-09 — Episode list focus ring removed so no blue outlines after clicking rows.
- 2025-03-09 — Player surfaces now respect appearance: control capsule and toolbar icons pull light/dark colors from `AppTheme`, staying bright in Light Mode and muted in Dark Mode.
- 2025-03-09 — Resolved concurrency warnings: AudioPlayer now awaits the async `scheduleSegment` API and debounces updates with `Task` sleeps; PersistenceManager’s save/load helpers require `Sendable` payloads.
- 2025-03-09 — Player card layout adjusted: progress/time labels sit below the transport bubble, and the speaker icon anchors an expanding volume slider that overlays the controls without shifting position.
- 2025-03-09 — Volume slider now expands from the control bubble’s speaker icon, overlays the transport controls, and collapses after adjustment. Player card layout restructured: enlarged artwork, title centered beneath it, and a tighter control bubble to resolve mid-list title overlap.
- 2025-03-09 — Show notes move into a dedicated toolbar popover that loads content in the background, PlayerView keeps artwork static, and ContentView orchestrates the new ShowNotesView experience. Toolbar button uses the Liquid Glass style and preloads show notes for the current episode.
- 2025-03-09 — AppTheme now resolves the live system appearance (macOS/iOS) and ContentView reuses it for toolbar coloring to keep light/dark parity. EpisodeListView regained its sorted cache helpers, and PodRamsApp uses the modern two-parameter `onChange` signature to avoid macOS 14 deprecation warnings.
- 2025-03-10 — Playback progress is now persisted per episode so the player resumes where you left off; AudioPlayer clears progress on completion and updates PlayedEpisodesManager when shows finish.
- 2025-09-26 — Help menu windows now persist via HelpWindowManager to prevent crashes, and show notes wrap long paragraphs with tappable links that open in the browser.

## Project Rules
- Always adhere to Liquid Glass design when writing code.
- Always respect cache, persistence, and translation requirements when adding features or changing code.
- Always code comment clearly so users understand intent.
- Each major code change or feature addition is documented in this file, including new Swift files.
- Always update this file when making rule-governed changes.
- Always respect dark and light mode behaviors.
- Ensure the latest Swift version requirements are met.
- Always optimize for CPU, memory, and speed.
- Always build and make sure it runs.
- Always add testcases for new functionality.
- Always make sure translation is always respected in all supported languages when adding new features.
