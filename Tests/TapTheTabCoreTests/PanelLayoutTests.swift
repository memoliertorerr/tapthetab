import XCTest
@testable import TapTheTabCore

/// The numbers pinned here were computed by the panel layout code before it moved from the
/// macOS UI layer into the core (TT25); the move must not change any of them.
final class PanelLayoutTests: XCTestCase {
    /// 14" MacBook Pro visible frame, the size the screenshots use.
    private let macBook = Size(width: 1512, height: 945)

    private func grid(
        _ count: Int,
        size: ItemSize = .medium,
        search: Bool = false,
        preview: Bool = false,
        screen: Size? = nil
    ) -> PanelLayout {
        PanelLayout.compute(style: .grid, size: size, itemCount: count, showsSearchBar: search,
                            screenSize: screen ?? macBook, showsPreview: preview)
    }

    private func list(_ count: Int, preview: Bool = false, headers: Int = 0, screen: Size? = nil) -> PanelLayout {
        PanelLayout.compute(style: .list, size: .medium, itemCount: count, showsSearchBar: true,
                            screenSize: screen ?? macBook, showsPreview: preview, sectionHeaderCount: headers)
    }

    // MARK: - Grid sizes per item count

    func testGridMediumPerItemCount() {
        let cases: [(count: Int, columns: Int, panel: Size)] = [
            (1, 1, Size(width: 360, height: 190)),
            (5, 5, Size(width: 928, height: 190)),
            (10, 7, Size(width: 1288, height: 352)),
            (11, 7, Size(width: 1288, height: 352)),
            (25, 7, Size(width: 1288, height: 676)),
        ]
        for c in cases {
            let layout = grid(c.count)
            XCTAssertEqual(layout.style, .grid)
            XCTAssertEqual(layout.columns, c.columns, "\(c.count) items")
            XCTAssertEqual(layout.panelSize, c.panel, "\(c.count) items")
            XCTAssertEqual(layout.itemSize, ItemSize.medium.cardSize, "full-size cards for \(c.count) items")
            XCTAssertFalse(layout.needsScrolling)
            XCTAssertFalse(layout.showsSearchBar)
            XCTAssertFalse(layout.showsPreview)
            XCTAssertEqual(layout.previewSize, .zero)
        }
    }

    func testGridPanelIsCardsPlusSpacingAndPadding() {
        // 5 medium cards: 5 × 168 + 4 × 12 + 2 × 20 wide, 150 + 2 × 20 tall.
        XCTAssertEqual(grid(5).panelSize, Size(width: 928, height: 190))
    }

    func testGridSmallAndLargeCards() {
        XCTAssertEqual(grid(10, size: .small).columns, 10)
        XCTAssertEqual(grid(10, size: .small).panelSize, Size(width: 1348, height: 150))
        XCTAssertEqual(grid(11, size: .small).panelSize, Size(width: 1348, height: 272))
        XCTAssertEqual(grid(3, size: .large).panelSize, Size(width: 760, height: 240))
        XCTAssertEqual(grid(6, size: .large).columns, 5)
        XCTAssertEqual(grid(6, size: .large).panelSize, Size(width: 1248, height: 452))
    }

    func testGridShrinksCardsBeforeScrolling() {
        let layout = grid(60)
        XCTAssertEqual(layout.columns, 10)
        XCTAssertEqual(layout.itemSize.width, 117.6, accuracy: 1e-9)
        XCTAssertEqual(layout.itemSize.height, 105, accuracy: 1e-9)
        XCTAssertEqual(layout.panelSize, Size(width: 1324, height: 730))
        XCTAssertFalse(layout.needsScrolling)
    }

    func testGridScrollsAtMinimumScale() {
        let layout = grid(200)
        XCTAssertEqual(layout.columns, 11)
        XCTAssertEqual(layout.itemSize.width, 168 * GridLayout.minimumScale, accuracy: 1e-9)
        XCTAssertEqual(layout.itemSize.height, 150 * GridLayout.minimumScale, accuracy: 1e-9)
        XCTAssertTrue(layout.needsScrolling)
        // 945 × 0.9 = 850.5, rounded up.
        XCTAssertEqual(layout.panelSize, Size(width: 1269, height: 851))
    }

    func testGridOnOtherScreens() {
        let screen = Size(width: 1440, height: 900)
        XCTAssertEqual(grid(8, screen: screen).panelSize, Size(width: 1288, height: 352))
        XCTAssertEqual(grid(20, screen: screen).panelSize, Size(width: 1288, height: 514))
        let tiny = grid(5, size: .small, screen: Size(width: 320, height: 480))
        XCTAssertEqual(tiny.columns, 2)
        XCTAssertEqual(tiny.itemSize.width, 114, accuracy: 1e-9)
        XCTAssertEqual(tiny.panelSize, Size(width: 320, height: 378))
    }

    // MARK: - Search bar

    func testGridSearchBarAddsItsHeight() {
        XCTAssertEqual(grid(1, search: true).panelSize, Size(width: 520, height: 234))
        XCTAssertEqual(grid(10, search: true).panelSize, Size(width: 1288, height: 396))
        XCTAssertEqual(grid(25, search: true).panelSize, Size(width: 1288, height: 720))
        XCTAssertTrue(grid(1, search: true).showsSearchBar)
    }

    func testGridSearchBarLeavesLessRoomForCards() {
        // Cards get the screen height minus the search bar: (945 - 44) × 0.9 = 810.9, + 44.
        let layout = grid(200, search: true)
        XCTAssertTrue(layout.needsScrolling)
        XCTAssertEqual(layout.panelSize, Size(width: 1269, height: 855))
    }

    func testGridSearchBarNeedsMinimumWidth() {
        XCTAssertEqual(grid(1, search: true).panelSize.width, PanelLayout.minimumSearchWidth)
        XCTAssertEqual(grid(1, search: false).panelSize.width, PanelLayout.minimumSize.width)
        XCTAssertEqual(grid(1, size: .small, search: true, screen: Size(width: 800, height: 300)).panelSize.width, 520)
    }

    func testGridAvailableHeightNeverBelowFloor() {
        // A 230-point screen with a search bar would leave 186 points for cards; 200 is used.
        let layout = grid(4, size: .small, search: true, screen: Size(width: 1000, height: 230))
        let metrics = GridLayout.compute(itemCount: 4, screen: Size(width: 1000, height: 200),
                                         item: ItemSize.small.cardSize, spacing: 12, padding: 20)
        XCTAssertEqual(layout.columns, metrics.columns)
        XCTAssertEqual(layout.itemSize, metrics.itemSize)
    }

    // MARK: - List

    func testListHeightPerItemCount() {
        // Search bar 44 + rows × 44 + 2 × 8 padding, at least 120.
        let cases: [(count: Int, height: Double)] = [
            (1, 120), (2, 148), (3, 192), (5, 280), (8, 412), (10, 500),
        ]
        for c in cases {
            let layout = list(c.count)
            XCTAssertEqual(layout.panelSize, Size(width: 640, height: c.height), "\(c.count) items")
            XCTAssertFalse(layout.needsScrolling, "\(c.count) items")
        }
    }

    func testListShowsAtMostTenRows() {
        for count in [11, 12, 25, 200] {
            let layout = list(count)
            XCTAssertEqual(layout.panelSize, Size(width: 640, height: 500), "\(count) items")
            XCTAssertTrue(layout.needsScrolling, "\(count) items")
        }
        // Even on a tall screen.
        let tall = Size(width: 2560, height: 1415)
        XCTAssertEqual(list(10, screen: tall).panelSize.height, 500)
        XCTAssertFalse(list(10, screen: tall).needsScrolling)
        XCTAssertEqual(list(40, screen: tall).panelSize.height, 500)
        XCTAssertTrue(list(40, screen: tall).needsScrolling)
        XCTAssertEqual(PanelLayout.listMaxRows, 10)
    }

    func testListShowsFewerRowsOnShortScreens() {
        // 480 × 0.9 - 44 - 16 = 372 → 8 rows.
        let small = list(11, screen: Size(width: 320, height: 480))
        XCTAssertEqual(small.panelSize, Size(width: 304, height: 412))
        XCTAssertTrue(small.needsScrolling)
        // 300 × 0.9 - 60 = 210 → 4 rows, so 5 items already scroll.
        let short = list(5, screen: Size(width: 800, height: 300))
        XCTAssertEqual(short.panelSize, Size(width: 640, height: 236))
        XCTAssertTrue(short.needsScrolling)
        XCTAssertFalse(list(4, screen: Size(width: 800, height: 300)).needsScrolling)
    }

    func testListAlwaysShowsAtLeastOneRow() {
        let layout = list(3, screen: Size(width: 800, height: 100))
        XCTAssertTrue(layout.needsScrolling)
        XCTAssertLessThanOrEqual(layout.panelSize.height, 100, "never taller than the screen")
    }

    func testListWidthAndRows() {
        let layout = list(3)
        XCTAssertEqual(layout.style, .list)
        XCTAssertEqual(layout.columns, 1)
        XCTAssertEqual(layout.itemSize, Size(width: 640, height: 44))
        XCTAssertTrue(layout.showsSearchBar)
        // Narrow screen: 95% of its width.
        XCTAssertEqual(list(3, screen: Size(width: 320, height: 480)).itemSize.width, 304)
        XCTAssertEqual(list(3, screen: Size(width: 320, height: 480)).panelSize.width, 304)
    }

    func testListAlwaysHasSearchBarAndIgnoresCardSize() {
        let without = PanelLayout.compute(style: .list, size: .large, itemCount: 4, showsSearchBar: false, screenSize: macBook)
        XCTAssertTrue(without.showsSearchBar)
        XCTAssertEqual(without, list(4))
    }

    // MARK: - Section headings (grouping by app)

    func testListSectionHeadersAddHeight() {
        // 5 rows + 2 headings: 44 + 5 × 44 + 2 × 24 + 16.
        let layout = list(5, headers: 2)
        XCTAssertEqual(layout.panelSize.height, 328)
        XCTAssertFalse(layout.needsScrolling)
        XCTAssertEqual(list(8, headers: 3).panelSize.height, 484, "44 + 8 × 44 + 3 × 24 + 16")
    }

    func testListSectionHeadersCountTowardsTheTenRowHeight() {
        // 10 rows fit exactly; with headings they no longer do, and the list scrolls at
        // the same height as without headings.
        let layout = list(10, headers: 3)
        XCTAssertTrue(layout.needsScrolling)
        XCTAssertEqual(layout.panelSize, list(10).panelSize)
        XCTAssertEqual(list(9, headers: 1).panelSize.height, 480, "44 + 9 × 44 + 24 + 16")
        XCTAssertFalse(list(9, headers: 1).needsScrolling)
        XCTAssertTrue(list(9, headers: 2).needsScrolling)
    }

    func testListSectionHeaderCountIsClamped() {
        XCTAssertEqual(list(2, headers: 50), list(2, headers: 2))
        XCTAssertEqual(list(4, headers: -3), list(4))
        XCTAssertEqual(list(0, headers: 3), list(0), "no headings in an empty list")
    }

    func testGridIgnoresSectionHeaders() {
        let plain = grid(7)
        let headed = PanelLayout.compute(style: .grid, size: .medium, itemCount: 7, showsSearchBar: false,
                                         screenSize: macBook, sectionHeaderCount: 3)
        XCTAssertEqual(plain, headed)
    }

    func testNoSectionHeadersMatchesDefault() {
        for count in [0, 1, 5, 10, 11, 50] {
            XCTAssertEqual(list(count, headers: 0),
                           PanelLayout.compute(style: .list, size: .medium, itemCount: count, showsSearchBar: true, screenSize: macBook))
        }
    }

    // MARK: - Empty state and minimum sizes

    func testEmptyGrid() {
        let layout = grid(0)
        XCTAssertEqual(layout.panelSize, PanelLayout.minimumSize, "100 points of content, raised to the minimum height")
        XCTAssertEqual(layout.columns, 1)
        XCTAssertFalse(layout.needsScrolling)
        XCTAssertEqual(grid(0, search: true).panelSize, Size(width: 520, height: 144))
    }

    func testEmptyList() {
        let layout = list(0)
        XCTAssertEqual(layout.panelSize, Size(width: 640, height: 144))
        XCTAssertFalse(layout.needsScrolling)
    }

    func testMinimumSizes() {
        XCTAssertEqual(PanelLayout.minimumSize, Size(width: 360, height: 120))
        XCTAssertEqual(grid(1, size: .small).panelSize, Size(width: 360, height: 150), "one small card is narrower than the minimum")
        XCTAssertEqual(list(1).panelSize.height, 120, "one row is lower than the minimum")
    }

    func testPanelNeverExceedsTheScreen() {
        let screens = [Size(width: 320, height: 480), Size(width: 800, height: 300), Size(width: 1024, height: 640),
                       macBook, Size(width: 2560, height: 1415), Size(width: 200, height: 150)]
        for screen in screens {
            for style in LayoutStyle.allCases {
                for size in ItemSize.allCases {
                    for count in [0, 1, 3, 9, 10, 11, 30, 120] {
                        for search in [false, true] {
                            for preview in [false, true] {
                                let layout = PanelLayout.compute(style: style, size: size, itemCount: count, showsSearchBar: search,
                                                                 screenSize: screen, showsPreview: preview)
                                let label = "\(screen) \(style) \(size) \(count) search=\(search) preview=\(preview)"
                                XCTAssertLessThanOrEqual(layout.panelSize.width, screen.width, label)
                                XCTAssertLessThanOrEqual(layout.panelSize.height, screen.height, label)
                                XCTAssertGreaterThanOrEqual(layout.columns, 1, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testNarrowScreenCapsMinimumWidth() {
        XCTAssertEqual(grid(1, screen: Size(width: 320, height: 480)).panelSize.width, 320)
        XCTAssertEqual(grid(0, search: true, screen: Size(width: 320, height: 480)).panelSize, Size(width: 320, height: 144))
    }

    func testInitial() {
        let initial = PanelLayout.initial
        XCTAssertEqual(initial.style, .grid)
        XCTAssertEqual(initial.columns, 1)
        XCTAssertEqual(initial.itemSize, ItemSize.medium.cardSize)
        XCTAssertFalse(initial.showsSearchBar)
        XCTAssertFalse(initial.needsScrolling)
        XCTAssertEqual(initial.panelSize, PanelLayout.minimumSize)
        XCTAssertFalse(initial.showsPreview)
    }

    // MARK: - Large preview

    func testPreviewIsCappedByScreenFraction() {
        // 945 × 0.45 = 425.25 → 425; the box spans the panel minus 16 on each side.
        let layout = grid(5, preview: true)
        XCTAssertEqual(layout.previewSize, Size(width: 896, height: 425))
        XCTAssertTrue(layout.showsPreview)
        XCTAssertEqual(layout.panelSize, Size(width: 928, height: 635), "190 + 16 + 425 + 4")
    }

    func testPreviewIsCappedByAspectRatio() {
        // Panel 360 wide → box 328 wide → at most 328 × 0.75 = 246 tall.
        let layout = grid(1, preview: true)
        XCTAssertEqual(layout.previewSize, Size(width: 328, height: 246))
        XCTAssertEqual(layout.panelSize, Size(width: 360, height: 456), "190 + 16 + 246 + 4")
    }

    func testPreviewIsCappedByRoomOnScreen() {
        // 850.5 - 676 - 16 - 4 = 154.5 → 154.
        let layout = grid(25, preview: true)
        XCTAssertEqual(layout.previewSize, Size(width: 1256, height: 154))
        XCTAssertEqual(layout.panelSize.height, 850)
        let list10 = list(10, preview: true)
        XCTAssertEqual(list10.previewSize, Size(width: 608, height: 330))
        XCTAssertEqual(list10.panelSize, Size(width: 640, height: 850))
    }

    func testPreviewIsSkippedWhenTooSmall() {
        // 850.5 - 730 - 20 = 100.5 < 120: no preview, the grid is unchanged.
        let layout = grid(60, preview: true)
        XCTAssertFalse(layout.showsPreview)
        XCTAssertEqual(layout.previewSize, .zero)
        XCTAssertEqual(layout, grid(60))
    }

    func testScrollingGridGetsNoPreview() {
        for size in ItemSize.allCases {
            for search in [false, true] {
                let layout = grid(200, size: size, search: search, preview: true)
                XCTAssertTrue(layout.needsScrolling)
                XCTAssertFalse(layout.showsPreview)
                XCTAssertEqual(layout, grid(200, size: size, search: search))
            }
        }
    }

    func testScrollingListStillGetsPreview() {
        // The list stops at 10 rows, far from the screen height.
        let layout = list(11, preview: true)
        XCTAssertTrue(layout.needsScrolling)
        XCTAssertEqual(layout.previewSize, Size(width: 608, height: 330))
    }

    func testPreviewNeverReflowsTheCards() {
        for count in [1, 5, 10, 25] {
            let plain = grid(count)
            let withPreview = grid(count, preview: true)
            XCTAssertEqual(withPreview.columns, plain.columns)
            XCTAssertEqual(withPreview.itemSize, plain.itemSize)
            XCTAssertEqual(withPreview.needsScrolling, plain.needsScrolling)
            XCTAssertEqual(withPreview.panelSize.width, plain.panelSize.width)
            if withPreview.showsPreview {
                XCTAssertEqual(withPreview.panelSize.height,
                               plain.panelSize.height + 16 + withPreview.previewSize.height + 4)
            }
        }
    }

    func testPreviewBoxRules() {
        let screen = Size(width: 1000, height: 1000)
        XCTAssertNil(PanelLayout.previewBox(panelWidth: 151, contentHeight: 50, screenSize: screen), "narrower than 120")
        // 160 × 0.75 = 120 is the smallest landscape box; 159 × 0.75 rounds down below it.
        XCTAssertNil(PanelLayout.previewBox(panelWidth: 191, contentHeight: 50, screenSize: screen))
        XCTAssertEqual(PanelLayout.previewBox(panelWidth: 192, contentHeight: 50, screenSize: screen), Size(width: 160, height: 120))
        XCTAssertEqual(PanelLayout.previewBox(panelWidth: 600, contentHeight: 100, screenSize: screen), Size(width: 568, height: 426))
        // Room: 900 - content - 20.
        XCTAssertEqual(PanelLayout.previewBox(panelWidth: 900, contentHeight: 640, screenSize: screen), Size(width: 868, height: 240))
        XCTAssertEqual(PanelLayout.previewBox(panelWidth: 900, contentHeight: 700, screenSize: screen), Size(width: 868, height: 180))
        XCTAssertEqual(PanelLayout.previewBox(panelWidth: 900, contentHeight: 760, screenSize: screen), Size(width: 868, height: 120))
        XCTAssertNil(PanelLayout.previewBox(panelWidth: 900, contentHeight: 761, screenSize: screen))
        // Screen fraction: 0.45 × 1000.
        XCTAssertEqual(PanelLayout.previewBox(panelWidth: 2000, contentHeight: 0, screenSize: screen)?.height, 450)
    }

    func testPreviewBoxDegenerateInputs() {
        XCTAssertNil(PanelLayout.previewBox(panelWidth: 0, contentHeight: 0, screenSize: .zero))
        XCTAssertNil(PanelLayout.previewBox(panelWidth: 1000, contentHeight: 0, screenSize: .zero))
        XCTAssertNil(PanelLayout.previewBox(panelWidth: .nan, contentHeight: 0, screenSize: Size(width: 1000, height: 1000)))
        XCTAssertNil(PanelLayout.previewBox(panelWidth: 1000, contentHeight: .infinity, screenSize: Size(width: 1000, height: 1000)))
    }

    func testPreviewOnShortScreenIsSkipped() {
        let short = Size(width: 800, height: 300)
        XCTAssertFalse(grid(1, preview: true, screen: short).showsPreview)
        XCTAssertEqual(list(1, preview: true, screen: short).previewSize, Size(width: 608, height: 130))
        XCTAssertFalse(list(5, preview: true, screen: short).showsPreview)
    }
}
