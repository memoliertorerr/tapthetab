import Foundation

/// How the window catalog found an entry. Shortcuts can choose different desktop
/// coverage, but there is one catalog: it looks as far as the broadest shortcut needs and
/// remembers where each entry came from, so a narrower switcher never shows what only a
/// broader pass found.
public enum ItemOrigin: String, CaseIterable, Sendable {
    /// Listed by the Accessibility API (or an app's own entry), also when reused from an
    /// earlier refresh.
    case listed
    /// Kept from an earlier refresh while a full-screen app is shown
    /// (`SeenWindowRetention`, public interfaces only).
    case retained
    /// Found only in the window server's lists of other Spaces (private interfaces).
    case otherSpaces
}

/// What the catalog looks for beyond the Accessibility API, for every coverage in use.
public struct DesktopDiscovery: Equatable, Sendable {
    /// Ask the window server for other Spaces' windows (an all-desktops coverage is in use).
    public var listsOtherSpaces: Bool
    /// Keep windows seen earlier while a full-screen app is shown (the default coverage
    /// is in use).
    public var retainsSeenWindows: Bool

    public init(listsOtherSpaces: Bool = false, retainsSeenWindows: Bool = false) {
        self.listsOtherSpaces = listsOtherSpaces
        self.retainsSeenWindows = retainsSeenWindows
    }

    public init<S: Sequence>(coverages: S) where S.Element == SpaceCoverage {
        var lists = false
        var retains = false
        for coverage in coverages {
            switch coverage {
            case .currentDesktop: break
            case .automatic: retains = true
            case .allDesktops: lists = true
            }
        }
        self.init(listsOtherSpaces: lists, retainsSeenWindows: retains)
    }

    /// What the configured shortcuts (and the filters' own choice) need.
    public init(_ configuration: Configuration) {
        self.init(coverages: configuration.desktopCoveragesInUse)
    }

    /// Whether a refresh keeps seen windows: for the default coverage, and for all
    /// desktops when the other Spaces could not be listed (the private functions are
    /// missing), as before.
    public func keepsSeenWindows(otherSpacesListed: Bool) -> Bool {
        retainsSeenWindows || (listsOtherSpaces && !otherSpacesListed)
    }

    /// A catalog built with this discovery has looked everywhere `coverage` shows.
    public func covers(_ coverage: SpaceCoverage) -> Bool {
        switch coverage {
        case .currentDesktop: return true
        case .automatic: return retainsSeenWindows
        case .allDesktops: return listsOtherSpaces
        }
    }
}

/// The catalog as one coverage sees it.
public enum CoverageView {
    /// Whether entries with `origin` belong to `coverage` while they are off the
    /// current Space.
    public static func shows(_ origin: ItemOrigin, coverage: SpaceCoverage) -> Bool {
        switch origin {
        case .listed: return true
        case .retained: return coverage != .currentDesktop
        case .otherSpaces: return coverage == .allDesktops
        }
    }

    /// `items` (catalog order) as a switcher with `coverage` sees them, before
    /// `ItemFilter`. `origins` holds the entries that were not simply listed.
    ///
    /// Windows from a pass this coverage doesn't use are left out unless they are on the
    /// current Space now. An app's own entry (no listed windows) stands in for its
    /// windows only where none of them is left, as when the catalog looks no further;
    /// an app whose every entry was left out gets one, at the end, like the catalog's.
    /// The order of what remains never changes.
    public static func items(_ items: [SwitcherItem], origins: [ItemID: ItemOrigin], coverage: SpaceCoverage) -> [SwitcherItem] {
        var windowPIDs = Set<Int32>()
        var droppedPIDs: [Int32] = []
        var droppedFirst: [Int32: SwitcherItem] = [:]
        var dropped = Set<ItemID>()
        for item in items where !item.isWindowless {
            let origin = origins[item.id] ?? .listed
            if item.isOnActiveSpace || shows(origin, coverage: coverage) {
                windowPIDs.insert(item.pid)
            } else {
                dropped.insert(item.id)
                if droppedFirst[item.pid] == nil {
                    droppedFirst[item.pid] = item
                    droppedPIDs.append(item.pid)
                }
            }
        }

        var result: [SwitcherItem] = []
        result.reserveCapacity(items.count)
        var appEntryPIDs = Set<Int32>()
        for item in items {
            if item.isWindowless {
                guard !windowPIDs.contains(item.pid), appEntryPIDs.insert(item.pid).inserted else { continue }
                result.append(item)
            } else if !dropped.contains(item.id) {
                result.append(item)
            }
        }
        for pid in droppedPIDs where !windowPIDs.contains(pid) && !appEntryPIDs.contains(pid) {
            guard let first = droppedFirst[pid] else { continue }
            result.append(SwitcherItem(id: .app(pid: pid), pid: pid, appName: first.appName, bundleID: first.bundleID, isAppHidden: first.isAppHidden))
        }
        return result
    }

    /// The entries TapTheTab itself saw (listed or kept before), which the seen-window
    /// pass may keep: never windows only the other-Spaces pass found, so the default
    /// coverage stays public-only although another shortcut lists every desktop.
    public static func seenItems(_ items: [SwitcherItem], origins: [ItemID: ItemOrigin]) -> [SwitcherItem] {
        guard !origins.isEmpty else { return items }
        return items.filter { origins[$0.id] != .otherSpaces }
    }
}
