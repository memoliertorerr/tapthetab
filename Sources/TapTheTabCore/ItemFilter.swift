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
    public var excludedBundleIDs: [String] = []

    public init(
        showMinimized: Bool = true,
        showHiddenApps: Bool = true,
        showWindowlessApps: Bool = false,
        currentSpaceOnly: Bool = false,
        currentDisplayOnly: Bool = false,
        excludedBundleIDs: [String] = []
    ) {
        self.showMinimized = showMinimized
        self.showHiddenApps = showHiddenApps
        self.showWindowlessApps = showWindowlessApps
        self.currentSpaceOnly = currentSpaceOnly
        self.currentDisplayOnly = currentDisplayOnly
        self.excludedBundleIDs = excludedBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FilterOptions()
        showMinimized = c.lenient(Bool.self, .showMinimized) ?? d.showMinimized
        showHiddenApps = c.lenient(Bool.self, .showHiddenApps) ?? d.showHiddenApps
        showWindowlessApps = c.lenient(Bool.self, .showWindowlessApps) ?? d.showWindowlessApps
        currentSpaceOnly = c.lenient(Bool.self, .currentSpaceOnly) ?? d.currentSpaceOnly
        currentDisplayOnly = c.lenient(Bool.self, .currentDisplayOnly) ?? d.currentDisplayOnly
        excludedBundleIDs = c.lenientArray(String.self, .excludedBundleIDs) ?? d.excludedBundleIDs
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
        var result = items.filter { item in
            if let own = context.ownPID, item.pid == own { return false }
            if let bundle = item.bundleID, excluded.contains(bundle.lowercased()) { return false }
            if item.isWindowless && !options.showWindowlessApps { return false }
            if item.isMinimized && !options.showMinimized { return false }
            if item.isAppHidden && !options.showHiddenApps { return false }
            if options.currentSpaceOnly && !item.isOnActiveSpace && !item.isMinimized && !item.isAppHidden && !item.isWindowless {
                return false
            }
            if options.currentDisplayOnly, let active = context.activeDisplayID,
               let display = item.displayID, display != active {
                return false
            }
            return true
        }

        switch scope {
        case .allWindows:
            break
        case .activeApp:
            if let pid = context.activePID {
                result = result.filter { $0.pid == pid && !$0.isWindowless }
            }
        case .apps:
            var seen = Set<Int32>()
            result = result.filter { seen.insert($0.pid).inserted }
        }
        return result
    }
}
