import os

/// Unified logging. Window titles are user data: always log them with `privacy: .private`.
enum Log {
    private static let subsystem = "io.github.memoliertorerr.TapTheTab"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let windows = Logger(subsystem: subsystem, category: "windows")
    static let config = Logger(subsystem: subsystem, category: "config")
}
