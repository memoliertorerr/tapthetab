import Foundation

/// What a switcher invocation shows.
public enum SwitcherScope: String, Codable, Sendable, CaseIterable {
    /// Every window of every app (the default ⌥⇥ behaviour).
    case allWindows
    /// Only windows of the app that is frontmost when the switcher opens.
    case activeApp
    /// One entry per app, like ⌘⇥, represented by its most recent window.
    case apps
}

/// User-tunable filters. Every field has a default so older config files keep working.
public struct FilterOptions: Codable, Equatable, Sendable {
    public var showMinimized: Bool = true
    public var showHiddenApps: Bool = true
    public var showWindowlessApps: Bool = false
    public var currentSpaceOnly: Bool = false
    public var currentDisplayOnly: Bool = false
    /// List windows on other Spaces (including fullscreen Spaces) too. Off by default: it
    /// relies on private macOS interfaces. `currentSpaceOnly` still hides those windows.
    public var showOtherSpaces: Bool = false
    public var excludedBundleIDs: [String] = []
    /// Apps listed before all others (`ItemOrdering.pinnedFirst`), by bundle ID,
    /// compared case-insensitively.
    public var pinnedBundleIDs: [String] = []

    public init(
        showMinimized: Bool = true,
        showHiddenApps: Bool = true,
        showWindowlessApps: Bool = false,
        currentSpaceOnly: Bool = false,
        currentDisplayOnly: Bool = false,
        showOtherSpaces: Bool = false,
        excludedBundleIDs: [String] = [],
        pinnedBundleIDs: [String] = []
    ) {
        self.showMinimized = showMinimized
        self.showHiddenApps = showHiddenApps
        self.showWindowlessApps = showWindowlessApps
        self.currentSpaceOnly = currentSpaceOnly
        self.currentDisplayOnly = currentDisplayOnly
        self.showOtherSpaces = showOtherSpaces
        self.excludedBundleIDs = excludedBundleIDs
        self.pinnedBundleIDs = pinnedBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FilterOptions()
        showMinimized = c.lenient(Bool.self, .showMinimized) ?? d.showMinimized
        showHiddenApps = c.lenient(Bool.self, .showHiddenApps) ?? d.showHiddenApps
        showWindowlessApps = c.lenient(Bool.self, .showWindowlessApps) ?? d.showWindowlessApps
        currentSpaceOnly = c.lenient(Bool.self, .currentSpaceOnly) ?? d.currentSpaceOnly
        currentDisplayOnly = c.lenient(Bool.self, .currentDisplayOnly) ?? d.currentDisplayOnly
        showOtherSpaces = c.lenient(Bool.self, .showOtherSpaces) ?? d.showOtherSpaces
        excludedBundleIDs = c.lenientArray(String.self, .excludedBundleIDs) ?? d.excludedBundleIDs
        pinnedBundleIDs = c.lenientArray(String.self, .pinnedBundleIDs) ?? d.pinnedBundleIDs
    }
}

/// Facts about the moment the switcher opens, used by the filters.
public struct FilterContext: Equatable, Sendable {
    public var activePID: Int32?
    public var activeDisplayID: UInt32?
    /// Our own process, which is never listed.
    public var ownPID: Int32?

    public init(activePID: Int32? = nil, activeDisplayID: UInt32? = nil, ownPID: Int32? = nil) {
        self.activePID = activePID
        self.activeDisplayID = activeDisplayID
        self.ownPID = ownPID
    }
}

public enum ItemFilter {
    /// Applies filters and scope to items that are already in recency order.
    /// The relative order of the surviving items never changes.
    public static func apply(
        _ items: [SwitcherItem],
        options: FilterOptions,
        scope: SwitcherScope,
        context: FilterContext
    ) -> [SwitcherItem] {
        let excluded = Set(options.excludedBundleIDs.map { $0.lowercased() })
        func passes(_ item: SwitcherItem, allowWindowless: Bool) -> Bool {
            if let own = context.ownPID, item.pid == own { return false }
            if let bundle = item.bundleID, excluded.contains(bundle.lowercased()) { return false }
            if item.isWindowless && !options.showWindowlessApps && !allowWindowless { return false }
            if item.isMinimized && !options.showMinimized { return false }
            if item.isAppHidden && !options.showHiddenApps { return false }
            // Windows listed from other Spaces (`showOtherSpaces`) are never minimized or
            // hidden, so this also removes them.
            if options.currentSpaceOnly && !item.isOnActiveSpace && !item.isMinimized && !item.isAppHidden && !item.isWindowless {
                return false
            }
            if options.currentDisplayOnly, let active = context.activeDisplayID,
               let display = item.displayID, display != active {
                return false
            }
            return true
        }
        var result = items.filter { passes($0, allowWindowless: false) }

        switch scope {
        case .allWindows:
            break
        case .activeApp:
            if let pid = context.activePID {
                result = result.filter { $0.pid == pid && !$0.isWindowless }
                // A frontmost app with no (remaining) windows would leave an empty panel:
                // show its windowless entry instead, even when windowless apps are hidden,
                // so it can be activated (which reopens a window). Every other filter,
                // including exclusions and our own PID, still applies.
                if result.isEmpty,
                   let app = items.first(where: { $0.pid == pid && $0.isWindowless && passes($0, allowWindowless: true) }) {
                    result = [app]
                }
            }
        case .apps:
            var seen = Set<Int32>()
            result = result.filter { seen.insert($0.pid).inserted }
        }
        return result
    }
}
