PodRams - A Modern macOS Podcast Player

PodRams is a native macOS podcast player built with SwiftUI, offering a clean and intuitive interface for podcast enthusiasts. It combines powerful features with a simple, elegant design.

Features
    •    🎧 Smart Playback: Seamless audio playback for both streaming and downloaded episodes
    •    📥 Download Management: Download episodes for offline listening
    •    📑 Cue System: Create and manage playlists with drag-and-drop support
    •    🔍 Search: Search for podcasts using the iTunes podcast directory
    •    ⭐ Favorites: Mark and easily access your favorite podcasts
    •    📝 Subscriptions: Subscribe to podcasts and automatically receive new episodes
    •    🖼️ Artwork Support: High-quality podcast artwork display
    •    💾 Persistence: Your favorites, subscriptions, and cue are automatically saved
    •    📱 Audio Output Selection: Choose between different audio output devices

Audio Controls
    •    Volume control
    •    Audio panning (left and right)
    •    Audio balance adjustment
    •    Playback speed control
    •    Skip silence (experimental)
    •    Keyboard shortcuts:
    •    M to mute
    •    + to increase volume
    •    - to decrease volume

Transcription
    •    🗒️ Podcast Transcription: Transcribe episodes into exportable text
    •    Powered by the Apple Whisper API
    •    View ongoing and completed transcriptions

Episode Management
    •    Option to hide played episodes from the episode list
    •    Improved layout with enlarged podcast artwork
    •    Transcribe button placed directly next to each episode for easy access

Technical Details
    •    Built with SwiftUI and AVFoundation
    •    Uses Combine for reactive programming
    •    Integrates Apple Whisper API for transcription workflows
    •    Implements efficient caching for images and audio
    •    Supports RSS feed parsing for podcast updates
    •    Handles both local and streaming audio playback
    •    Implements drag-and-drop for playlist management

Requirements
    •    macOS 11.0 or later
    •    Xcode 13.0 or later (for development)

Supported Languages

PodRams supports a wide variety of languages thanks to community contributions and localization efforts. Currently supported languages include:

Arabic (ar), Bulgarian (bg), Basque (eu), Catalan (ca), Czech (cs), Danish (da), German (de), Greek (el), English (en), Spanish (es), Finnish (fi), French (fr), Hebrew (he), Hindi (hi), Croatian (hr), Hungarian (hu), Indonesian (id), Italian (it), Japanese (ja), Korean (ko), Malay (ms), Norwegian Bokmål (nb), Dutch (nl), Polish (pl), Portuguese (pt), Brazilian Portuguese (pt-BR), Romanian (ro), Russian (ru), Slovak (sk), Slovenian (sl), Serbian (sr), Swedish (sv), Thai (th), Turkish (tr), Ukrainian (uk), Vietnamese (vi), Simplified Chinese (zh-Hans), Traditional Chinese (zh-Hant)

Installation
    1.    Clone the repository
    2.    Open PodRams.xcodeproj in Xcode
    3.    Build and run the project

Usage
    1.    Search for Podcasts: Click the search icon and enter a podcast name
    2.    Subscribe: Click the subscribe button on any podcast to add it to your subscriptions
    3.    Download Episodes: Click the download icon on any episode to save it for offline listening
    4.    Create Playlists: Drag episodes to the cue to build custom playlists
    5.    Manage Favorites: Star your favorite podcasts for quick access
    6.    Transcribe Episodes: Use the episode-level transcribe button to generate text with the Apple Whisper API
    7.    Hide Played Episodes: Enable the option to automatically hide completed episodes

Contributing

Contributions are welcome. Please feel free to submit a Pull Request.

License

This project is licensed under the MIT License. See the LICENSE file for details.

Acknowledgments
    •    Thanks to the SwiftUI team for the framework
    •    iTunes API for podcast directory access
    •    Apple Whisper API for transcription capabilities
    •    All the podcast creators who make great content

Contact

For questions or feedback, please open an issue in the repository.
