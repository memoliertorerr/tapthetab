import Foundation

/// Things a window or app can have done to it from the switcher.
public enum WindowAction: String, Codable, Sendable, CaseIterable {
    case focus
    case close
    case minimize
    case toggleFullscreen
    case hideApp
    case quitApp
    /// Move the window to the next display (wrapping), keeping its relative position.
    case moveToNextDisplay
    /// Close every window of the item's app; the app keeps running.
    case closeAppWindows
    /// Pin or unpin the item's app (by bundle ID): pinned apps are listed first.
    case togglePin
}

/// Input to a running switcher session, already decoded from raw key/mouse events.
public enum SwitcherInput: Equatable, Sendable {
    case next
    case previous
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case first
    case last
    case type(String)
    case deleteBackward
    case select(index: Int)
    /// Pick the item at this index of `visible` and switch to it at once (⌘1…⌘9).
    case quickSelect(index: Int)
    /// Show or hide a large peek at the selected window (⇧Space).
    case peek
    /// Keep the switcher open after the trigger modifiers are released.
    case lockOpen
    case commit
    case cancel
    /// The modifiers of the trigger shortcut were released.
    case triggerReleased
    case action(WindowAction)
}

/// What the platform layer should do after an input.
public enum SwitcherEffect: Equatable, Sendable {
    /// Nothing visible changed.
    case none
    /// Selection, query or items changed; redraw.
    case refresh
    /// Close the switcher and bring this item to the front.
    case activate(SwitcherItem)
    /// Run an action on an item; the switcher stays open.
    case perform(WindowAction, SwitcherItem)
    /// Toggle the peek overlay for this window; the switcher stays open.
    case peek(SwitcherItem)
    /// Close the switcher without doing anything.
    case dismiss
}

/// One visible row/cell: the item plus how it matched the current query.
public struct RankedItem: Equatable, Sendable, Identifiable {
    public var item: SwitcherItem
    public var match: FuzzyMatch?
    public var id: ItemID { item.id }

    public init(item: SwitcherItem, match: FuzzyMatch? = nil) {
        self.item = item
        self.match = match
    }
}

/// The switcher's state machine. Pure value type: feed it inputs, act on the effects.
///
/// Typical flow: the trigger (⌥⇥) creates a session with the second item selected,
/// further presses of ⇥ cycle, typing filters, and releasing ⌥ activates the selection.
public struct SwitcherSession: Equatable, Sendable {
    public private(set) var items: [SwitcherItem]
    public private(set) var query: String = ""
    public private(set) var visible: [RankedItem] = []
    public private(set) var selectedIndex: Int?
    /// When true, releasing the trigger modifiers does not activate; ↩ or a click does.
    public private(set) var isLocked: Bool
    /// Columns in the current layout, used for ↑/↓ navigation in a grid. 1 for lists.
    public var columns: Int {
        didSet { columns = max(1, columns) }
    }
    public var wrapsAround: Bool
    /// Selects the second entry on open, so a quick tap switches to the previous window.
    public let startsOnPrevious: Bool
    /// Past picks for past queries. While searching, items are ranked by
    /// `match.score + searchMemory.boost(query:for:)`; it never affects the empty-query
    /// order and never adds items that did not match. The session only reads it: the app
    /// records a pick (`record(query:picked:)`) when a search session activates an item.
    public private(set) var searchMemory: SearchMemory

    public init(
        items: [SwitcherItem],
        startsOnPrevious: Bool = true,
        locked: Bool = false,
        columns: Int = 1,
        wrapsAround: Bool = true,
        searchMemory: SearchMemory = SearchMemory()
    ) {
        self.items = items
        self.startsOnPrevious = startsOnPrevious
        self.isLocked = locked
        self.columns = max(1, columns)
        self.wrapsAround = wrapsAround
        self.searchMemory = searchMemory
        recompute(keeping: nil)
    }

    public var selectedItem: SwitcherItem? {
        guard let i = selectedIndex, visible.indices.contains(i) else { return nil }
        return visible[i].item
    }

    public var isSearching: Bool { !query.isEmpty }

    @discardableResult
    public mutating func handle(_ input: SwitcherInput) -> SwitcherEffect {
        switch input {
        case .next: return step(by: 1)
        case .previous: return step(by: -1)
        case .moveRight: return step(by: 1)
        case .moveLeft: return step(by: -1)
        case .moveDown: return columns > 1 ? stepRow(by: 1) : step(by: 1)
        case .moveUp: return columns > 1 ? stepRow(by: -1) : step(by: -1)
        case .first: return select(0)
        case .last: return select(visible.count - 1)
        case .select(let index): return select(index)

        case .quickSelect(let index):
            guard visible.indices.contains(index) else { return .none }
            selectedIndex = index
            return .activate(visible[index].item)

        case .peek:
            guard let item = selectedItem, !item.isWindowless else { return .none }
            return .peek(item)

        case .type(let text):
            let cleaned = text.filter { !$0.isNewline && $0 != "\t" }
            guard !cleaned.isEmpty else { return .none }
            // A leading space would match nothing useful; ignore it.
            if query.isEmpty && cleaned.allSatisfy(\.isWhitespace) { return .none }
            query += cleaned
            recompute(keeping: nil)
            return .refresh

        case .deleteBackward:
            guard !query.isEmpty else { return .none }
            query.removeLast()
            recompute(keeping: query.isEmpty ? nil : selectedItem?.id)
            return .refresh

        case .lockOpen:
            guard !isLocked else { return .none }
            isLocked = true
            return .refresh

        case .commit:
            if let item = selectedItem { return .activate(item) }
            return .dismiss

        case .triggerReleased:
            if isLocked { return .none }
            if let item = selectedItem { return .activate(item) }
            return .dismiss

        case .cancel:
            if !query.isEmpty {
                query = ""
                recompute(keeping: nil)
                return .refresh
            }
            return .dismiss

        case .action(let action):
            guard let item = selectedItem else { return .none }
            if action == .focus { return .activate(item) }
            // Actions that need a window make no sense for a windowless app entry, and an
            // app with no windows has none to close.
            if item.isWindowless, Self.windowOnlyActions.contains(action) { return .none }
            // Pins are stored by bundle ID; an item without one cannot be pinned.
            if action == .togglePin, (item.bundleID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .none
            }
            return .perform(action, item)
        }
    }

    /// Swap in a fresh item list (for example after closing a window), keeping the
    /// selection on the same item when it still exists, otherwise on the same position.
    public mutating func replaceItems(_ newItems: [SwitcherItem]) {
        let previousID = selectedItem?.id
        let previousIndex = selectedIndex
        items = newItems
        recompute(keeping: previousID)
        if let previousID, !visible.contains(where: { $0.id == previousID }) {
            if visible.isEmpty {
                selectedIndex = nil
            } else if let previousIndex {
                selectedIndex = min(previousIndex, visible.count - 1)
            }
        }
    }

    /// Actions ignored for windowless app entries.
    static let windowOnlyActions: Set<WindowAction> = [
        .close, .minimize, .toggleFullscreen, .moveToNextDisplay, .closeAppWindows,
    ]

    // MARK: - Private

    private mutating func recompute(keeping id: ItemID?) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            visible = items.map { RankedItem(item: $0) }
        } else {
            let boost = searchMemory.scorer(for: query)
            let scored = items.enumerated().compactMap { offset, item -> (offset: Int, rank: Int, item: RankedItem)? in
                guard let match = FuzzyMatcher.match(query, item: item) else { return nil }
                // The boost is only added to items that already matched.
                return (offset, match.score + boost(item), RankedItem(item: item, match: match))
            }
            visible = scored.sorted { a, b in
                a.rank != b.rank ? a.rank > b.rank : a.offset < b.offset
            }.map(\.item)
        }

        if let id, let index = visible.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        } else if visible.isEmpty {
            selectedIndex = nil
        } else if query.isEmpty && startsOnPrevious && visible.count > 1 {
            selectedIndex = 1
        } else {
            selectedIndex = 0
        }
    }

    private mutating func select(_ index: Int) -> SwitcherEffect {
        guard visible.indices.contains(index), index != selectedIndex else { return .none }
        selectedIndex = index
        return .refresh
    }

    private mutating func step(by delta: Int) -> SwitcherEffect {
        guard !visible.isEmpty else { return .none }
        guard let current = selectedIndex else { return select(delta >= 0 ? 0 : visible.count - 1) }
        var next = current + delta
        if wrapsAround {
            next = ((next % visible.count) + visible.count) % visible.count
        } else {
            next = min(max(next, 0), visible.count - 1)
        }
        return select(next)
    }

    private mutating func stepRow(by rows: Int) -> SwitcherEffect {
        guard !visible.isEmpty, let current = selectedIndex else { return step(by: rows) }
        let target = current + rows * columns
        if visible.indices.contains(target) { return select(target) }
        let column = current % columns
        if rows > 0 {
            // A partial last row has a gap under this column: land on the last item
            // (like Finder) instead of wrapping past a row that still exists.
            let lastRow = (visible.count - 1) / columns
            if current / columns < lastRow { return select(visible.count - 1) }
            // Already on the last row: wrap to the same column on the first row.
            guard wrapsAround else { return .none }
            return select(column < visible.count ? column : 0)
        }
        // Moving up from the first row: wrap to the same column on the last row,
        // or to the last item when that row is too short.
        guard wrapsAround else { return .none }
        let lastRowStart = ((visible.count - 1) / columns) * columns
        let candidate = lastRowStart + column
        return select(candidate < visible.count ? candidate : visible.count - 1)
    }
}
