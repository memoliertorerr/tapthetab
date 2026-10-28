import CoreGraphics
import TapTheTabCore

/// `PanelLayout` (the sizing math, in the core and tested there) in CoreGraphics types,
/// computed once per update by `SwitcherPanelController` so the SwiftUI views never
/// measure anything themselves.
struct SwitcherLayout: Equatable {
    static let searchBarHeight = CGFloat(PanelLayout.searchBarHeight)
    static let listWidth = CGFloat(PanelLayout.listWidth)
    static let listRowHeight = CGFloat(PanelLayout.listRowHeight)
    static let listMaxRows: Int = PanelLayout.listMaxRows
    static let listPadding = CGFloat(PanelLayout.listPadding)
    static let listSectionHeaderHeight = CGFloat(PanelLayout.listSectionHeaderHeight)
    static let gridSpacing = CGFloat(PanelLayout.gridSpacing)
    static let gridPadding = CGFloat(PanelLayout.gridPadding)
    static let minimumSize = CGSize(PanelLayout.minimumSize)
    static let fallbackScreenSize = CGSize(PanelLayout.fallbackScreenSize)
    static let previewInset = CGFloat(PanelLayout.previewInset)
    static let previewBottomGap = CGFloat(PanelLayout.previewBottomGap)

    /// The core's result; everything below reads from it.
    var core: PanelLayout

    var style: LayoutStyle { core.style }
    var columns: Int { core.columns }
    /// Card size (grid) or row size (list).
    var itemSize: CGSize { CGSize(core.itemSize) }
    var showsSearchBar: Bool { core.showsSearchBar }
    var needsScrolling: Bool { core.needsScrolling }
    var panelSize: CGSize { CGSize(core.panelSize) }
    /// Box for the large preview of the selected window above the grid or list, or
    /// `.zero` when it is not shown. Included in `panelSize`.
    var previewSize: CGSize { CGSize(core.previewSize) }
    var showsPreview: Bool { core.showsPreview }

    static let initial = SwitcherLayout(core: PanelLayout.initial)

    /// See `PanelLayout.compute`.
    static func compute(
        style: LayoutStyle,
        size: ItemSize,
        itemCount: Int,
        showsSearchBar: Bool,
        screenSize: CGSize,
        showsPreview: Bool = false,
        sectionHeaderCount: Int = 0
    ) -> SwitcherLayout {
        SwitcherLayout(core: PanelLayout.compute(
            style: style,
            size: size,
            itemCount: itemCount,
            showsSearchBar: showsSearchBar,
            screenSize: Size(screenSize),
            showsPreview: showsPreview,
            sectionHeaderCount: sectionHeaderCount
        ))
    }
}

extension CGSize {
    init(_ size: Size) {
        self.init(width: CGFloat(size.width), height: CGFloat(size.height))
    }
}

extension Size {
    init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
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
