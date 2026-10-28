import AppKit
import TapTheTabCore

// Contracts between the system layer (System/, App/) and the UI layer (UI/).
// Keep these small and stable: both sides compile against them.

/// Permission state and the ways to request it.
@MainActor
protocol PermissionsProviding: AnyObject {
    /// Accessibility: required for the keyboard shortcut and for window control.
    var accessibilityGranted: Bool { get }
    /// Screen Recording: only required for live window previews.
    var screenRecordingGranted: Bool { get }
    /// Shows the system prompt (if macOS still allows it) and opens System Settings.
    func requestAccessibility()
    func requestScreenRecording()
    func openAccessibilitySettings()
    func openScreenRecordingSettings()
}

/// Start-at-login toggle (SMAppService on macOS 13+).
@MainActor
protocol LaunchAtLoginProviding: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Read-only facts about the running app, for About screens.
enum AppInfo {
    static var name: String { "TapTheTab" }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static let repositoryURL = URL(string: "https://github.com/memoliertorerr/tapthetab")!
    static let issuesURL = URL(string: "https://github.com/memoliertorerr/tapthetab/issues")!
}
