import Foundation

extension Size {
    public static let zero = Size(width: 0, height: 0)
}

/// Every size the switcher panel needs, worked out from the item count, the style and
/// the screen: card or row size, columns, whether the content scrolls, the panel size
/// and the box for the large preview. The macOS layer converts the result to CoreGraphics
/// sizes (`SwitcherLayout`) so its views never measure anything themselves.
///
/// All sizes are in points. The panel is never taller or wider than the screen size given
/// (the visible frame of the display, without menu bar and Dock).
public struct PanelLayout: Equatable, Sendable {
    public static let searchBarHeight: Double = 44
    public static let listWidth: Double = 640
    public static let listRowHeight: Double = 44
    /// List rows showing a window thumbnail instead of the app icon are taller, so the
    /// thumbnail is big enough to recognise the window.
    public static let listThumbnailRowHeight: Double = 60
    public static let listMaxRows: Int = 10
    public static let listPadding: Double = 8
    /// Height of the app-name heading above each app's first row when the list is
    /// grouped by app (`Appearance.groupByApp`).
    public static let listSectionHeaderHeight: Double = 24
    public static let gridSpacing: Double = 12
    public static let gridPadding: Double = 20
    public static let minimumSize = Size(width: 360, height: 120)
    /// Grid panels with a search bar need room for the query and the key hints.
    public static let minimumSearchWidth: Double = 520
    public static let emptyContentHeight: Double = 100
    /// Used when no screen is known yet.
    public static let fallbackScreenSize = Size(width: 1440, height: 900)
    /// Large preview of the selected window (previews mode). It sits on its own card that
    /// floats above the grid or list: the full-size box is the panel's width minus this
    /// inset on each side…
    public static let previewInset: Double = 16
    /// …the card frames the image with this padding…
    public static let previewCardPadding: Double = 5
    /// …and this much empty space separates the card from the grid or list below it.
    public static let previewGap: Double = 10
    /// Height the card and the gap add on top of the box itself.
    public static var previewChromeHeight: Double { previewCardPadding * 2 + previewGap }
    /// Range of `previewScale` (fraction of the full-size box); other values are clamped.
    public static let previewScaleRange: ClosedRange<Double> = 0.25...1
    /// The preview box is at most this fraction of the screen's visible height…
    public static let previewScreenFraction: Double = 0.45
    /// …and at most this tall relative to its width (4:3), so landscape windows fill it.
    public static let previewMaxHeightToWidth: Double = 0.75
    /// A smaller box than this is not worth showing; the preview is skipped instead.
    public static let minimumPreviewHeight: Double = 120
    /// The whole panel stays within this fraction of the screen's visible height
    /// (the same fraction `GridLayout` uses).
    public static let maxPanelScreenFraction: Double = 0.9
    /// The list is at most this fraction of the screen's width.
    public static let listMaxScreenWidthFraction: Double = 0.95
    /// The grid never gets less than this much height to lay out cards in.
    public static let minimumGridAvailableHeight: Double = 200

    public var style: LayoutStyle
    public var columns: Int
    /// Card size (grid) or row size (list).
    public var itemSize: Size
    public var showsSearchBar: Bool
    public var needsScrolling: Bool
    public var panelSize: Size
    /// Box for the large preview of the selected window above the grid or list, or
    /// `.zero` when it is not shown. The image is aspect-fit inside it. Included, with
    /// its card and the gap below it, in `panelSize`.
    public var previewSize: Size

    public var showsPreview: Bool { previewSize.width > 0 && previewSize.height > 0 }

    /// The preview's card at its largest (the box plus padding), or `.zero`.
    public var previewCardSize: Size {
        guard showsPreview else { return .zero }
        return Size(width: previewSize.width + Self.previewCardPadding * 2,
                    height: previewSize.height + Self.previewCardPadding * 2)
    }

    /// Height above the grid or list taken by the preview card and the gap below it.
    public var previewAreaHeight: Double {
        showsPreview ? previewCardSize.height + Self.previewGap : 0
    }

    /// The grid or list block (search bar included), below the preview area.
    public var mainSize: Size {
        Size(width: panelSize.width, height: max(0, panelSize.height - previewAreaHeight))
    }

    /// The preview card for an image of `imageSize`: the image aspect-fit in the box plus
    /// padding, so the card hugs the window's shape. The whole box (plus padding) when the
    /// image size is unknown or degenerate. `.zero` when no preview is shown.
    public func previewCardSize(fitting imageSize: Size?) -> Size {
        guard showsPreview else { return .zero }
        guard let imageSize,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else {
            return previewCardSize
        }
        let scale = min(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
        let width = max(1, (imageSize.width * scale).rounded())
        let height = max(1, (imageSize.height * scale).rounded())
        return Size(width: min(width, previewSize.width) + Self.previewCardPadding * 2,
                    height: min(height, previewSize.height) + Self.previewCardPadding * 2)
    }

    public init(
        style: LayoutStyle,
        columns: Int,
        itemSize: Size,
        showsSearchBar: Bool,
        needsScrolling: Bool,
        panelSize: Size,
        previewSize: Size = .zero
    ) {
        self.style = style
        self.columns = columns
        self.itemSize = itemSize
        self.showsSearchBar = showsSearchBar
        self.needsScrolling = needsScrolling
        self.panelSize = panelSize
        self.previewSize = previewSize
    }

    /// Before anything was laid out: an empty medium grid at the minimum size.
    public static let initial = PanelLayout(
        style: .grid,
        columns: 1,
        itemSize: ItemSize.medium.cardSize,
        showsSearchBar: false,
        needsScrolling: false,
        panelSize: minimumSize
    )

    /// - Parameters:
    ///   - showsPreview: reserve room for a large preview of the selected window above the
    ///     grid or list. The grid or list itself is laid out exactly as without it (same
    ///     columns and card size), so the preview never reflows the cards; when the panel
    ///     would grow past the screen the preview is skipped (`previewSize == .zero`).
    ///   - previewScale: size of the preview box relative to the full-size box (1), clamped
    ///     to `previewScaleRange`; not a number counts as 1.
    ///   - listThumbnails: list rows show window thumbnails (`listThumbnailRowHeight`).
    ///   - sectionHeaderCount: app-name headings shown between the rows of a list grouped
    ///     by app (ignored by the grid). Clamped to `0...itemCount`.
    public static func compute(
        style: LayoutStyle,
        size: ItemSize,
        itemCount: Int,
        showsSearchBar: Bool,
        screenSize: Size,
        showsPreview: Bool = false,
        previewScale: Double = 1,
        sectionHeaderCount: Int = 0,
        listThumbnails: Bool = false
    ) -> PanelLayout {
        var layout: PanelLayout
        switch style {
        case .list:
            layout = computeList(itemCount: itemCount, sectionHeaderCount: sectionHeaderCount, screenSize: screenSize,
                                 rowHeight: listThumbnails ? listThumbnailRowHeight : listRowHeight)
        case .grid:
            layout = computeGrid(size: size, itemCount: itemCount, showsSearchBar: showsSearchBar, screenSize: screenSize)
        }
        if showsPreview,
           let box = previewBox(panelWidth: layout.panelSize.width, contentHeight: layout.panelSize.height,
                                screenSize: screenSize, scale: previewScale) {
            layout.previewSize = box
            layout.panelSize.height += previewChromeHeight + box.height
        }
        return layout
    }

    /// The large preview's box for a panel `panelWidth` wide whose other content is
    /// `contentHeight` tall, or nil when no box of at least `minimumPreviewHeight` fits
    /// without the panel exceeding `maxPanelScreenFraction` of the screen height.
    /// `scale` shrinks the full-size box (width and height alike) before the room on
    /// screen is taken into account.
    public static func previewBox(panelWidth: Double, contentHeight: Double, screenSize: Size, scale: Double = 1) -> Size? {
        let factor = clampedPreviewScale(scale)
        let width = ((panelWidth - previewInset * 2) * factor).rounded(.down)
        guard width >= minimumPreviewHeight else { return nil }
        let room = screenSize.height * maxPanelScreenFraction - contentHeight - previewChromeHeight
        let height = min(
            screenSize.height * previewScreenFraction * factor,
            width * previewMaxHeightToWidth,
            room
        ).rounded(.down)
        guard height.isFinite, height >= minimumPreviewHeight else { return nil }
        return Size(width: width, height: height)
    }

    /// `scale` within `previewScaleRange`; not a number (or infinite) counts as 1.
    public static func clampedPreviewScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1 }
        return min(max(scale, previewScaleRange.lowerBound), previewScaleRange.upperBound)
    }

    private static func computeGrid(size: ItemSize, itemCount: Int, showsSearchBar: Bool, screenSize: Size) -> PanelLayout {
        let searchHeight: Double = showsSearchBar ? searchBarHeight : 0
        let available = Size(
            width: screenSize.width,
            height: max(screenSize.height - searchHeight, minimumGridAvailableHeight)
        )
        let metrics = GridLayout.compute(
            itemCount: itemCount,
            screen: available,
            item: size.cardSize,
            spacing: gridSpacing,
            padding: gridPadding
        )

        var width = metrics.contentSize.width
        var height = metrics.contentSize.height + searchHeight
        if itemCount == 0 {
            height = searchHeight + emptyContentHeight
        }
        width = max(width, showsSearchBar ? minimumSearchWidth : minimumSize.width)
        height = max(height, minimumSize.height)
        width = min(width, screenSize.width)
        height = min(height, screenSize.height)

        return PanelLayout(
            style: .grid,
            columns: max(1, metrics.columns),
            itemSize: metrics.itemSize,
            showsSearchBar: showsSearchBar,
            needsScrolling: metrics.needsScrolling,
            panelSize: Size(width: width.rounded(.up), height: height.rounded(.up))
        )
    }

    /// The list always shows its search bar. It shows up to `listMaxRows` rows (fewer on a
    /// short screen) and scrolls beyond that; section headings count towards the same height.
    private static func computeList(itemCount: Int, sectionHeaderCount: Int, screenSize: Size, rowHeight: Double) -> PanelLayout {
        let usableHeight = screenSize.height * maxPanelScreenFraction - searchBarHeight - listPadding * 2
        let rowsByScreen = max(1, Int(usableHeight / rowHeight))
        let rowLimit = min(listMaxRows, rowsByScreen)
        let count = max(itemCount, 0)
        let headers = min(max(sectionHeaderCount, 0), count)

        let rowsHeight = Double(count) * rowHeight + Double(headers) * listSectionHeaderHeight
        let maxRowsHeight = Double(rowLimit) * rowHeight
        let contentHeight: Double
        if count == 0 {
            contentHeight = emptyContentHeight
        } else {
            contentHeight = min(rowsHeight, maxRowsHeight) + listPadding * 2
        }
        let width = min(listWidth, screenSize.width * listMaxScreenWidthFraction)
        var height = searchBarHeight + contentHeight
        height = max(height, minimumSize.height)
        height = min(height, screenSize.height)

        return PanelLayout(
            style: .list,
            columns: 1,
            itemSize: Size(width: width, height: rowHeight),
            showsSearchBar: true,
            needsScrolling: rowsHeight > maxRowsHeight,
            panelSize: Size(width: width.rounded(.up), height: height.rounded(.up))
        )
    }
}
