import Foundation

/// Optional re-orderings of the switcher's items, applied after recency ordering and
/// `ItemFilter` and before the items reach `SwitcherSession`.
public enum ItemOrdering {
    /// Moves the items of pinned apps (`FilterOptions.pinnedBundleIDs`, compared
    /// case-insensitively) to the front. A stable partition: pinned items keep their
    /// order among themselves (recency, not the order of the pin list), and so do the
    /// others. Items without a bundle ID (or with an empty one) are never pinned. Nothing
    /// is added or dropped.
    ///
    /// With `groupedByApp` the two can run in either order and give the same list: all
    /// of an app's items share its bundle ID, so the pinned apps' groups come first, each
    /// group intact, apps in each part in the order of their most recent window.
    public static func pinnedFirst(_ items: [SwitcherItem], pinnedBundleIDs: Set<String>) -> [SwitcherItem] {
        let pinned = Set(pinnedBundleIDs.lazy.map { $0.lowercased() }.filter { !$0.isEmpty })
        guard !pinned.isEmpty else { return items }
        var front: [SwitcherItem] = []
        var back: [SwitcherItem] = []
        for item in items {
            if let bundle = item.bundleID?.lowercased(), pinned.contains(bundle) {
                front.append(item)
            } else {
                back.append(item)
            }
        }
        return front + back
    }

    /// Moves the items on `displayID` (the display the switcher opens on) to the front
    /// (`FilterOptions.currentDisplayFirst`). A stable partition: both parts keep their
    /// order (recency). Items with an unknown display, and windowless app entries (which
    /// have no display), go to the second part. A nil `displayID` changes nothing.
    /// Nothing is added or dropped.
    ///
    /// Composition: apply this before `pinnedFirst`. Both are stable partitions, so the
    /// result is pinned apps' items on this display, pinned apps' items elsewhere, other
    /// items on this display, then the rest: pinned apps still lead. Applied after
    /// `groupedByApp` it can split an app's group across the two parts; apply it before
    /// grouping to keep groups whole: apps with a window on this display then come
    /// before the others, each group intact.
    public static func displayFirst(_ items: [SwitcherItem], displayID: UInt32?) -> [SwitcherItem] {
        guard let displayID else { return items }
        var front: [SwitcherItem] = []
        var back: [SwitcherItem] = []
        for item in items {
            if !item.isWindowless, item.displayID == displayID {
                front.append(item)
            } else {
                back.append(item)
            }
        }
        return front + back
    }

    /// Whether `item`'s app is pinned (bundle IDs compared case-insensitively), e.g. for
    /// a pin badge or the "Pin"/"Unpin" wording of the ⇧P action.
    public static func isPinned(_ item: SwitcherItem, pinnedBundleIDs: [String]) -> Bool {
        guard let bundle = item.bundleID?.lowercased(), !bundle.isEmpty else { return false }
        return pinnedBundleIDs.contains { $0.lowercased() == bundle }
    }

    /// Groups the items by app (`Appearance.groupByApp`): apps in the order of their
    /// first item, each followed by all of its items in their original order.
    ///
    /// Given items in recency order this puts the apps in the order of their most recent
    /// window, and each app's windows in recency order. Stable; nothing is added or
    /// dropped. Apps are told apart by process, so two running copies of an app are two
    /// groups.
    public static func groupedByApp(_ items: [SwitcherItem]) -> [SwitcherItem] {
        var order: [Int32] = []
        var groups: [Int32: [SwitcherItem]] = [:]
        for item in items {
            if groups[item.pid] == nil {
                order.append(item.pid)
                groups[item.pid] = [item]
            } else {
                groups[item.pid]?.append(item)
            }
        }
        guard order.count > 1, order.count < items.count else { return items }
        var result: [SwitcherItem] = []
        result.reserveCapacity(items.count)
        for pid in order {
            result.append(contentsOf: groups[pid] ?? [])
        }
        return result
    }

    /// Indices of the items that get an app-name heading above them in a list grouped by
    /// app: the first item of each run of items from the same app.
    ///
    /// Empty (no headings) unless grouping is on, the style is the list, there is no
    /// search (search results are ranked, not grouped), and the headings add something:
    /// at least two apps and at least one app with more than one item. A list with one
    /// item per app (such as the "apps" scope) or a single app (such as the "active app"
    /// scope) already shows each row's app name.
    public static func sectionHeaderIndices(
        for items: [SwitcherItem],
        groupByApp: Bool,
        style: LayoutStyle,
        isSearching: Bool
    ) -> [Int] {
        guard groupByApp, style == .list, !isSearching, items.count > 1 else { return [] }
        var starts: [Int] = []
        var previous: Int32?
        for (index, item) in items.enumerated() where item.pid != previous {
            starts.append(index)
            previous = item.pid
        }
        guard starts.count > 1, starts.count < items.count else { return [] }
        return starts
    }
}
