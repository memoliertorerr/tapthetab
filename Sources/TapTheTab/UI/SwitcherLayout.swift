import CoreGraphics
import TapTheTabCore

/// Everything the switcher views need to know about sizes, computed once per update
/// by `SwitcherPanelController` so the SwiftUI views never measure anything themselves.
struct SwitcherLayout: Equatable {
    static let searchBarHeight: CGFloat = 44
    static let listWidth: CGFloat = 640
    static let listRowHeight: CGFloat = 44
    static let listMaxRows: Int = 10
    static let listPadding: CGFloat = 8
    static let gridSpacing: CGFloat = 12
    static let gridPadding: CGFloat = 20
    static let minimumSize = CGSize(width: 360, height: 120)
    /// Grid panels with a search bar need room for the query and the key hints.
    static let minimumSearchWidth: CGFloat = 520
    static let emptyContentHeight: CGFloat = 100
    /// Used when no screen is known yet.
    static let fallbackScreenSize = CGSize(width: 1440, height: 900)

    var style: LayoutStyle
    var columns: Int
    /// Card size (grid) or row size (list).
    var itemSize: CGSize
    var showsSearchBar: Bool
    var needsScrolling: Bool
    var panelSize: CGSize

    static let initial = SwitcherLayout(
        style: .grid,
        columns: 1,
        itemSize: CGSize(width: 168, height: 150),
        showsSearchBar: false,
        needsScrolling: false,
        panelSize: minimumSize
    )

    static func compute(
        style: LayoutStyle,
        size: ItemSize,
        itemCount: Int,
        showsSearchBar: Bool,
        screenSize: CGSize
    ) -> SwitcherLayout {
        switch style {
        case .list:
            return computeList(itemCount: itemCount, screenSize: screenSize)
        case .grid:
            return computeGrid(size: size, itemCount: itemCount, showsSearchBar: showsSearchBar, screenSize: screenSize)
        }
    }

    private static func computeGrid(size: ItemSize, itemCount: Int, showsSearchBar: Bool, screenSize: CGSize) -> SwitcherLayout {
        let searchHeight: CGFloat = showsSearchBar ? searchBarHeight : 0
        let available = Size(
            width: Double(screenSize.width),
            height: Double(max(screenSize.height - searchHeight, 200))
        )
        let metrics: GridMetrics = GridLayout.compute(
            itemCount: itemCount,
            screen: available,
            item: size.cardSize,
            spacing: Double(gridSpacing),
            padding: Double(gridPadding)
        )

        var width = CGFloat(metrics.contentSize.width)
        var height = CGFloat(metrics.contentSize.height) + searchHeight
        if itemCount == 0 {
            height = searchHeight + emptyContentHeight
        }
        width = max(width, showsSearchBar ? minimumSearchWidth : minimumSize.width)
        height = max(height, minimumSize.height)
        width = min(width, screenSize.width)
        height = min(height, screenSize.height)

        return SwitcherLayout(
            style: .grid,
            columns: max(1, metrics.columns),
            itemSize: CGSize(width: CGFloat(metrics.itemSize.width), height: CGFloat(metrics.itemSize.height)),
            showsSearchBar: showsSearchBar,
            needsScrolling: metrics.needsScrolling,
            panelSize: CGSize(width: width.rounded(.up), height: height.rounded(.up))
        )
    }

    private static func computeList(itemCount: Int, screenSize: CGSize) -> SwitcherLayout {
        let usableHeight = screenSize.height * 0.9 - searchBarHeight - listPadding * 2
        let rowsByScreen = max(1, Int(usableHeight / listRowHeight))
        let rowLimit = min(listMaxRows, rowsByScreen)
        let count = max(itemCount, 0)
        let shownRows = min(count, rowLimit)

        let contentHeight: CGFloat
        if count == 0 {
            contentHeight = emptyContentHeight
        } else {
            contentHeight = CGFloat(shownRows) * listRowHeight + listPadding * 2
        }
        let width = min(listWidth, screenSize.width * 0.95)
        var height = searchBarHeight + contentHeight
        height = max(height, minimumSize.height)
        height = min(height, screenSize.height)

        return SwitcherLayout(
            style: .list,
            columns: 1,
            itemSize: CGSize(width: width, height: listRowHeight),
            showsSearchBar: true,
            needsScrolling: count > rowLimit,
            panelSize: CGSize(width: width.rounded(.up), height: height.rounded(.up))
        )
    }
}

/// One cell of the grid or one row of the list: the item plus its index in `session.visible`.
struct SwitcherCell: Identifiable {
    let index: Int
    let ranked: RankedItem
    var id: ItemID { ranked.id }

    static func cells(from visible: [RankedItem]) -> [SwitcherCell] {
        var result: [SwitcherCell] = []
        result.reserveCapacity(visible.count)
        for (offset, ranked) in visible.enumerated() {
            result.append(SwitcherCell(index: offset, ranked: ranked))
        }
        return result
    }
}

struct SwitcherGridRow: Identifiable {
    let id: Int
    let cells: [SwitcherCell]

    static func rows(from visible: [RankedItem], columns: Int) -> [SwitcherGridRow] {
        let all = SwitcherCell.cells(from: visible)
        let perRow = max(1, columns)
        var rows: [SwitcherGridRow] = []
        var start = 0
        while start < all.count {
            let end = min(start + perRow, all.count)
            rows.append(SwitcherGridRow(id: rows.count, cells: Array(all[start..<end])))
            start = end
        }
        return rows
    }
}
