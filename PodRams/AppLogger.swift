import OSLog

enum AppLogger {
    static let subsystem = "com.podrams.PodRams"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let downloads = Logger(subsystem: subsystem, category: "Downloads")
    static let networking = Logger(subsystem: subsystem, category: "Networking")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let debug = Logger(subsystem: subsystem, category: "Debug")
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    static let tests = Logger(subsystem: subsystem, category: "Tests")
    static let feed = Logger(subsystem: subsystem, category: "Feed")

    static func makeLogger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
