import Foundation

/// Stable identity of something the switcher can show.
public enum ItemID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// A real window, identified by its window-server number (CGWindowID on macOS).
    case window(UInt32)
    /// A running app that has no visible window.
    case app(pid: Int32)

    public var description: String {
        switch self {
        case .window(let number): return "window(\(number))"
        case .app(let pid): return "app(\(pid))"
        }
    }
}

/// A platform-neutral snapshot of one entry in the switcher.
///
/// The macOS layer fills these in from the window server and the Accessibility API;
/// everything in TapTheTabCore works only on these values, which keeps it testable.
public struct SwitcherItem: Hashable, Sendable, Identifiable {
    public var id: ItemID
    public var pid: Int32
    public var appName: String
    public var bundleID: String?
    public var title: String
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isFullscreen: Bool
    public var isOnActiveSpace: Bool
    /// Identifier of the display the window is mostly on, if known.
    public var displayID: UInt32?

    public init(
        id: ItemID,
        pid: Int32,
        appName: String,
        bundleID: String? = nil,
        title: String = "",
        isMinimized: Bool = false,
        isAppHidden: Bool = false,
        isFullscreen: Bool = false,
        isOnActiveSpace: Bool = true,
        displayID: UInt32? = nil
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isFullscreen = isFullscreen
        self.isOnActiveSpace = isOnActiveSpace
        self.displayID = displayID
    }

    /// True for entries that represent an app without any window.
    public var isWindowless: Bool {
        if case .app = id { return true }
        return false
    }

    /// The text shown as the main label: the window title, or the app name when untitled.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }
}
