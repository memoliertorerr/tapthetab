import XCTest
@testable import TapTheTabCore

final class GridLayoutTests: XCTestCase {
    private let card = Size(width: 100, height: 100)
    private let screen = Size(width: 1000, height: 1000)

    // usable width at scale 1: 1000 * 0.9 - 40 = 860; (860 + 12) / (100 + 12) = 7.78 → 7 per row.

    func testColumnsFitScreenWidth() {
        let m = GridLayout.compute(itemCount: 20, screen: screen, item: card)
        XCTAssertEqual(m.columns, 7)
        XCTAssertEqual(m.rows, 3)
        XCTAssertEqual(m.scale, 1)
        XCTAssertFalse(m.needsScrolling)
        XCTAssertEqual(m.itemSize, card)
        XCTAssertEqual(m.contentSize.width, 7 * 100 + 6 * 12 + 40)
        XCTAssertEqual(m.contentSize.height, 3 * 100 + 2 * 12 + 40)
        XCTAssertLessThanOrEqual(m.contentSize.width, screen.width * 0.9)
    }

    func testFewItemsUseFewerColumns() {
        let m = GridLayout.compute(itemCount: 3, screen: screen, item: card)
        XCTAssertEqual(m.columns, 3)
        XCTAssertEqual(m.rows, 1)
        XCTAssertEqual(m.contentSize, Size(width: 3 * 100 + 2 * 12 + 40, height: 140))
    }

    func testRowsRoundUp() {
        XCTAssertEqual(GridLayout.compute(itemCount: 7, screen: screen, item: card).rows, 1)
        XCTAssertEqual(GridLayout.compute(itemCount: 8, screen: screen, item: card).rows, 2)
        XCTAssertEqual(GridLayout.compute(itemCount: 14, screen: screen, item: card).rows, 2)
        XCTAssertEqual(GridLayout.compute(itemCount: 15, screen: screen, item: card).rows, 3)
    }

    func testSingleItem() {
        let m = GridLayout.compute(itemCount: 1, screen: screen, item: card)
        XCTAssertEqual(m.columns, 1)
        XCTAssertEqual(m.rows, 1)
        XCTAssertEqual(m.contentSize, Size(width: 140, height: 140))
        XCTAssertEqual(m.scale, 1)
    }

    func testZeroItems() {
        let m = GridLayout.compute(itemCount: 0, screen: screen, item: card)
        XCTAssertEqual(m.rows, 0)
        XCTAssertEqual(m.columns, 1)
        XCTAssertEqual(m.scale, 1)
        XCTAssertFalse(m.needsScrolling)
        XCTAssertEqual(m.contentSize.height, 40, "just the padding")
    }

    func testNegativeCountIsTreatedAsZero() {
        XCTAssertEqual(GridLayout.compute(itemCount: -5, screen: screen, item: card),
                       GridLayout.compute(itemCount: 0, screen: screen, item: card))
    }

    func testShrinksWhenTooTall() {
        // 60 items at full size: 7 per row → 9 rows → 9*100 + 8*12 + 40 = 1036 > 900.
        let m = GridLayout.compute(itemCount: 60, screen: screen, item: card)
        XCTAssertLessThan(m.scale, 1)
        XCTAssertGreaterThanOrEqual(m.scale, GridLayout.minimumScale)
        XCTAssertFalse(m.needsScrolling)
        XCTAssertLessThanOrEqual(m.contentSize.height, 900)
        XCTAssertEqual(m.itemSize.width, 100 * m.scale, accuracy: 1e-9)
        XCTAssertEqual(m.itemSize.height, 100 * m.scale, accuracy: 1e-9)
        XCTAssertGreaterThan(m.columns, 7, "smaller cards fit more per row")
        XCTAssertEqual(m.rows, Int((60.0 / Double(m.columns)).rounded(.up)))
    }

    func testShrinksOnlyAsMuchAsNeeded() {
        let m = GridLayout.compute(itemCount: 60, screen: screen, item: card)
        // One step larger would not have fit.
        let larger = m.scale + 0.05
        let w = 100 * larger
        let perRow = Int(((860 + 12) / (w + 12)).rounded(.down))
        let rows = Int((60.0 / Double(perRow)).rounded(.up))
        XCTAssertGreaterThan(Double(rows) * w + Double(rows - 1) * 12 + 40, 900)
    }

    func testStopsAtMinimumScaleAndScrolls() {
        let m = GridLayout.compute(itemCount: 500, screen: screen, item: card)
        XCTAssertEqual(m.scale, GridLayout.minimumScale, accuracy: 1e-9)
        XCTAssertTrue(m.needsScrolling)
        XCTAssertEqual(m.contentSize.height, 900, accuracy: 1e-9, "content is capped to the visible height")
        XCTAssertEqual(m.itemSize.width, 60, accuracy: 1e-9)
        XCTAssertGreaterThan(Double(m.rows) * 60, 900)
    }

    func testCustomSpacingPaddingAndFraction() {
        let m = GridLayout.compute(itemCount: 10, screen: Size(width: 500, height: 500), item: card,
                                   spacing: 0, padding: 0, maxScreenFraction: 1)
        XCTAssertEqual(m.columns, 5)
        XCTAssertEqual(m.rows, 2)
        XCTAssertEqual(m.contentSize, Size(width: 500, height: 200))
    }

    func testCardWiderThanScreenStillGetsOneColumn() {
        let m = GridLayout.compute(itemCount: 3, screen: Size(width: 100, height: 2000), item: Size(width: 400, height: 100))
        XCTAssertEqual(m.columns, 1)
        XCTAssertEqual(m.rows, 3)
    }

    func testWideSingleCardShrinksToFitWidth() {
        // Usable width 900 - 40 = 860; a 1000-wide card must shrink to fit it.
        let m = GridLayout.compute(itemCount: 1, screen: screen, item: Size(width: 1000, height: 200))
        XCTAssertLessThan(m.scale, 1)
        XCTAssertGreaterThanOrEqual(m.scale, GridLayout.minimumScale)
        XCTAssertEqual(m.columns, 1)
        XCTAssertLessThanOrEqual(m.contentSize.width, 900 + 1e-9)
        XCTAssertEqual(m.itemSize.width, 1000 * m.scale, accuracy: 1e-9)
        XCTAssertEqual(m.itemSize.height, 200 * m.scale, accuracy: 1e-9, "aspect ratio is kept")
        XCTAssertFalse(m.needsScrolling)
    }

    func testWidthShrinksOnlyAsMuchAsNeeded() {
        let m = GridLayout.compute(itemCount: 1, screen: screen, item: Size(width: 1000, height: 200))
        // 0.85 * 1000 + 40 = 890 fits; 0.9 * 1000 + 40 = 940 does not.
        XCTAssertEqual(m.scale, 0.85, accuracy: 1e-9)
        XCTAssertGreaterThan(1000 * (m.scale + 0.05) + 40, 900)
    }

    func testNarrowScreenShrinksCards() {
        // 300-point-wide screen: 270 - 40 = 230 usable; a 300-wide card scales to <= 230.
        let m = GridLayout.compute(itemCount: 4, screen: Size(width: 300, height: 2000), item: Size(width: 300, height: 100))
        XCTAssertEqual(m.columns, 1)
        XCTAssertEqual(m.rows, 4)
        XCTAssertLessThanOrEqual(m.contentSize.width, 270 + 1e-9)
        XCTAssertLessThanOrEqual(m.itemSize.width, 230 + 1e-9)
        XCTAssertGreaterThan(m.itemSize.width + 0.05 * 300, 230, "not shrunk more than one step too far")
    }

    func testTooWideEvenAtMinimumScaleStopsAtMinimum() {
        let m = GridLayout.compute(itemCount: 2, screen: Size(width: 100, height: 2000), item: Size(width: 1000, height: 100))
        XCTAssertEqual(m.scale, GridLayout.minimumScale, accuracy: 1e-9)
        XCTAssertEqual(m.columns, 1)
        XCTAssertEqual(m.itemSize.width, 600, accuracy: 1e-9)
        XCTAssertEqual(m.contentSize.width, 600 + 40, accuracy: 1e-9, "never narrower than one minimum-scale card")
        XCTAssertFalse(m.needsScrolling, "width never scrolls; height fits")
    }

    func testCardsThatFitWidthAreNotShrunk() {
        // Exactly the usable width: 860 + 40 = 900.
        let m = GridLayout.compute(itemCount: 1, screen: screen, item: Size(width: 860, height: 100))
        XCTAssertEqual(m.scale, 1)
        XCTAssertEqual(m.contentSize.width, 900, accuracy: 1e-9)
    }

    func testLargeCardsOnTinyScreenFitBothWays() {
        let m = GridLayout.compute(itemCount: 6, screen: Size(width: 320, height: 480), item: ItemSize.large.cardSize)
        XCTAssertLessThanOrEqual(m.contentSize.width, 320 * 0.9 + 1e-9)
        XCTAssertLessThan(m.scale, 1)
    }

    func testDegenerateSizesDoNotCrash() {
        let zero = GridLayout.compute(itemCount: 4, screen: Size(width: 0, height: 0), item: Size(width: 0, height: 0),
                                      spacing: 0, padding: 0)
        XCTAssertGreaterThanOrEqual(zero.columns, 1)
        XCTAssertLessThanOrEqual(zero.columns, 4)
        XCTAssertEqual(zero.rows, Int((4.0 / Double(zero.columns)).rounded(.up)))

        let huge = GridLayout.compute(itemCount: 3, screen: Size(width: 1e300, height: 1e300), item: Size(width: 1, height: 1))
        XCTAssertEqual(huge.columns, 3)
        XCTAssertEqual(huge.rows, 1)
    }

    func testRealisticMacBookScreen() {
        // 1512x982 points (14" MacBook Pro), medium cards, 25 windows.
        let m = GridLayout.compute(itemCount: 25, screen: Size(width: 1512, height: 982), item: ItemSize.medium.cardSize)
        XCTAssertFalse(m.needsScrolling)
        XCTAssertLessThanOrEqual(m.contentSize.width, 1512 * 0.9 + 1e-9)
        XCTAssertLessThanOrEqual(m.contentSize.height, 982 * 0.9 + 1e-9)
        XCTAssertGreaterThanOrEqual(m.columns * m.rows, 25)
        XCTAssertLessThan((m.columns) * (m.rows - 1), 25, "no completely empty last row")
    }
}
