import Foundation

/// Remembers the order in which windows and apps were focused (most recent first).
///
/// Items that were never seen focused keep the order the platform gave them
/// (front-to-back z-order on macOS), after every item that has a focus stamp.
public struct RecencyTracker: Sendable, Equatable {
    private var stamps: [ItemID: UInt64] = [:]
    private var clock: UInt64 = 0

    public init() {}

    /// Record that `id` just received focus.
    public mutating func touch(_ id: ItemID) {
        clock &+= 1
        stamps[id] = clock
    }

    public mutating func forget(_ id: ItemID) {
        stamps[id] = nil
    }

    /// Drop stamps for anything that no longer exists, so memory stays bounded.
    public mutating func prune(keeping alive: Set<ItemID>) {
        stamps = stamps.filter { alive.contains($0.key) }
    }

    public func stamp(for id: ItemID) -> UInt64? { stamps[id] }

    public var trackedCount: Int { stamps.count }

    /// Most recently focused first; unknown items keep their input order at the end.
    public func ordered(_ items: [SwitcherItem]) -> [SwitcherItem] {
        let indexed = items.enumerated().map { (offset: $0.offset, item: $0.element) }
        return indexed.sorted { a, b in
            switch (stamps[a.item.id], stamps[b.item.id]) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.item)
    }
}
