import Foundation

/// Remembers which item was chosen after typing which query ("frecency" for search), so the
/// next search for the same or a related query ranks that item higher.
///
/// Held in memory only: it is never encoded or written to disk.
///
/// ## Rules
///
/// **Queries** are normalised like `FuzzyMatcher` folds text: case-, diacritic- and
/// width-insensitive, trimmed, with runs of whitespace collapsed to one space. An empty
/// normalised query is never recorded and never boosts.
///
/// **What is remembered.** Each `record` stores one entry per (normalised query, item id),
/// together with the item's app key (`bundleID`, lowercased, or the folded `appName` when
/// there is no bundle ID), a pick count and a "last used" stamp from an internal counter
/// (no wall-clock time, so results are deterministic).
///
/// **Which entries apply.** An entry for remembered query `Q` applies to the current query
/// `C` when `C == Q`, `C` is a prefix of `Q` (typed less: `s` after picking for `sl`) or `Q`
/// is a prefix of `C` (typed more: `slac` after picking for `sl`). Its *relation* is
/// `50 + 50 × shorter / longer` percent — 100 % for the same query, 75 % for `s` vs `sl`.
///
/// **Points per entry** = `base × relation% × recency%`, rounded down, where
/// - `base` = `30 + 6 × (min(count, 6) − 1)`: 30 for one pick, up to 60 from six picks on;
/// - `recency%` = `max(30, 100 − 2 × age)`, `age` being the number of `record` calls since
///   the entry was last used (0 for the latest pick).
///
/// **Boost** for an item = `windowTier + appTier`, where
/// - `windowTier` is the best entry with the item's exact id *and* the same app key (the
///   app check guards against a window number being reused by another app), and
/// - `appTier` is half of the best entry with the same app key (any window of that app;
///   this survives the window closing and the app relaunching).
///
/// So the picked window gets 1.5× the points of its siblings, and an exact-window hit
/// always beats a same-app hit with the same history. The boost is at most
/// `60 + 30 = 90`: enough to reorder close matches (word start vs. mid-word, title length)
/// but not to lift a scattered subsequence match over a strong contiguous one after a
/// single pick. It is only ever added to items that already matched, so it can never make
/// a non-matching item appear.
///
/// **Size** is bounded by `capacity` entries; beyond it, the least recently used entries
/// are evicted. A capacity of 0 disables the memory.
public struct SearchMemory: Equatable, Sendable {
    /// Maximum number of (query, item) entries kept.
    public let capacity: Int

    struct Key: Hashable, Sendable {
        var query: String
        var id: ItemID
    }

    struct Entry: Equatable, Sendable {
        var appKey: String
        var count: Int
        var lastUsed: UInt64
    }

    private(set) var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0

    // Tuning constants; see the type documentation.
    static let basePoints = 30
    static let pointsPerRepeat = 6
    static let countSaturation = 6
    static let recencyDecayPerPick = 2
    static let recencyFloorPercent = 30
    /// Largest boost a single item can receive.
    public static let maximumBoost = (basePoints + pointsPerRepeat * (countSaturation - 1)) * 3 / 2

    public init(capacity: Int = 256) {
        self.capacity = max(0, capacity)
    }

    /// Number of remembered (query, item) entries.
    public var count: Int { entries.count }

    public var isEmpty: Bool { entries.isEmpty }

    /// Remember that `item` was chosen after typing `query`.
    public mutating func record(query: String, picked item: SwitcherItem) {
        let normalized = Self.normalize(query)
        guard capacity > 0, !normalized.isEmpty else { return }
        clock &+= 1
        let key = Key(query: normalized, id: item.id)
        var entry = entries[key] ?? Entry(appKey: Self.appKey(for: item), count: 0, lastUsed: 0)
        entry.appKey = Self.appKey(for: item)
        entry.count += 1
        entry.lastUsed = clock
        entries[key] = entry
        evictIfNeeded()
    }

    /// Score bonus to add to `FuzzyMatch.score` for `item` when the user has typed `query`.
    /// 0 when nothing is remembered.
    public func boost(query: String, for item: SwitcherItem) -> Int {
        scorer(for: query)(item)
    }

    /// Returns a function that computes `boost(query:for:)` for many items while
    /// normalising the query and selecting the applicable entries only once.
    func scorer(for query: String) -> (SwitcherItem) -> Int {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty, !entries.isEmpty else { return { _ in 0 } }

        var byWindow: [ItemID: [(appKey: String, points: Int)]] = [:]
        var byApp: [String: Int] = [:]
        for (key, entry) in entries {
            guard let relation = Self.relationPercent(current: normalized, remembered: key.query) else { continue }
            let points = points(for: entry, relationPercent: relation)
            guard points > 0 else { continue }
            byWindow[key.id, default: []].append((entry.appKey, points))
            byApp[entry.appKey] = max(byApp[entry.appKey] ?? 0, points)
        }
        guard !byApp.isEmpty else { return { _ in 0 } }

        return { item in
            let app = Self.appKey(for: item)
            let windowTier = byWindow[item.id]?
                .filter { $0.appKey == app }
                .map(\.points)
                .max() ?? 0
            let appTier = (byApp[app] ?? 0) / 2
            return windowTier + appTier
        }
    }

    // MARK: - Rules

    private func points(for entry: Entry, relationPercent: Int) -> Int {
        let repeats = min(entry.count, Self.countSaturation) - 1
        let base = Self.basePoints + Self.pointsPerRepeat * max(0, repeats)
        let age = clock &- entry.lastUsed
        let decay = age > UInt64(Int.max / Self.recencyDecayPerPick) ? Int.max : Int(age) * Self.recencyDecayPerPick
        let recency = max(Self.recencyFloorPercent, 100 - decay)
        return base * relationPercent * recency / 10_000
    }

    /// Percent weight of a remembered query for the current one, or nil when unrelated.
    static func relationPercent(current: String, remembered: String) -> Int? {
        guard current.hasPrefix(remembered) || remembered.hasPrefix(current) else { return nil }
        let a = current.count
        let b = remembered.count
        let shorter = min(a, b)
        let longer = max(a, b)
        guard longer > 0 else { return nil }
        return 50 + 50 * shorter / longer
    }

    private mutating func evictIfNeeded() {
        let excess = entries.count - capacity
        guard excess > 0 else { return }
        let oldest = entries.sorted { $0.value.lastUsed < $1.value.lastUsed }.prefix(excess)
        for (key, _) in oldest { entries[key] = nil }
    }

    /// Folds the query like `FuzzyMatcher` does, trims it and collapses whitespace.
    static func normalize(_ query: String) -> String {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map { String(FuzzyMatcher.fold(String($0))) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Identity of an item's app that survives windows closing and the app relaunching.
    static func appKey(for item: SwitcherItem) -> String {
        if let bundle = item.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !bundle.isEmpty {
            return "bundle:" + bundle.lowercased()
        }
        return "name:" + String(FuzzyMatcher.fold(item.appName.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
