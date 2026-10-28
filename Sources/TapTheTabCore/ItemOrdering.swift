import Foundation

/// Optional re-orderings of the switcher's items, applied after recency ordering and
/// `ItemFilter` and before the items reach `SwitcherSession`.
public enum ItemOrdering {
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
