import XCTest
@testable import TapTheTabCore

final class PanelPlacementTests: XCTestCase {
    /// A 1512 × 945 visible frame starting above a 25 pt Dock, like the screenshots' screen.
    private let screen = ScreenRect(x: 0, y: 25, width: 1512, height: 945)
    private let main = Size(width: 640, height: 300)
    private let card = Size(width: 420, height: 290)

    private func frames(_ main: Size? = nil, preview: Size? = nil, mainAt: BlockPosition? = nil, previewAt: BlockPosition? = nil,
                        on visible: ScreenRect? = nil) -> (main: ScreenRect, preview: ScreenRect?) {
        PanelPlacement.frames(visible: visible ?? screen, mainSize: main ?? self.main, previewSize: preview,
                              mainPosition: mainAt, previewPosition: previewAt)
    }

    private func assertInside(_ frame: ScreenRect, _ visible: ScreenRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY, file: file, line: line)
    }

    // MARK: - Defaults

    func testMainAloneIsCentred() {
        let result = frames()
        XCTAssertEqual(result.main, ScreenRect(x: 436, y: 348, width: 640, height: 300))
        XCTAssertNil(result.preview)
    }

    func testDefaultPairIsCentredTogetherWithTheCardAbove() {
        let result = frames(preview: card)
        // Together 290 + 10 + 300 = 600 tall, centred on 497.5: top 797.5.
        let preview = try! XCTUnwrap(result.preview)
        XCTAssertEqual(preview.maxY - result.main.minY, 600, accuracy: 1)
        XCTAssertEqual(preview.minY - result.main.maxY, PanelPlacement.gap, accuracy: 1)
        XCTAssertEqual(preview.midX, result.main.midX, accuracy: 1)
        XCTAssertEqual((preview.maxY + result.main.minY) / 2, screen.midY, accuracy: 1)
    }

    func testEmptyPreviewSizeMeansNoPreview() {
        XCTAssertNil(frames(preview: Size(width: 0, height: 100)).preview)
        XCTAssertNil(frames(preview: Size(width: 100, height: 0)).preview)
        XCTAssertEqual(frames(preview: .zero).main, frames().main)
    }

    // MARK: - Remembered positions

    func testMainAtRememberedPositionKeepsItsTopEdge() {
        let result = frames(mainAt: BlockPosition(x: 0.25, y: 0.9))
        XCTAssertEqual(result.main.midX, 378)
        XCTAssertEqual(result.main.maxY, 25 + 0.9 * 945, accuracy: 0.5)
        // Taller content grows downwards from the same top edge.
        let taller = frames(Size(width: 640, height: 500), mainAt: BlockPosition(x: 0.25, y: 0.9))
        XCTAssertEqual(taller.main.maxY, result.main.maxY)
    }

    func testCardFollowsAMovedMainBlock() {
        let result = frames(preview: card, mainAt: BlockPosition(x: 0.3, y: 0.5))
        let preview = try! XCTUnwrap(result.preview)
        XCTAssertEqual(preview.minY, result.main.maxY + PanelPlacement.gap)
        XCTAssertEqual(preview.midX, result.main.midX, accuracy: 1)
    }

    func testCardGoesBelowWhenNoRoomAbove() {
        let result = frames(preview: card, mainAt: BlockPosition(x: 0.5, y: 1))
        let preview = try! XCTUnwrap(result.preview)
        XCTAssertEqual(result.main.maxY, screen.maxY)
        XCTAssertEqual(preview.maxY, result.main.minY - PanelPlacement.gap)
        assertInside(preview, screen)
    }

    func testCardIsClampedWhenNeitherSideFits() {
        let tallMain = Size(width: 640, height: 800)
        let result = frames(tallMain, preview: card, mainAt: BlockPosition(x: 0.5, y: 0.9))
        assertInside(try! XCTUnwrap(result.preview), screen)
        assertInside(result.main, screen)
    }

    func testCardAtItsOwnRememberedPosition() {
        let result = frames(preview: card, mainAt: BlockPosition(x: 0.5, y: 0.5), previewAt: BlockPosition(x: 0.8, y: 0.1))
        let preview = try! XCTUnwrap(result.preview)
        XCTAssertEqual(preview.midX, 0.8 * 1512, accuracy: 1)
        XCTAssertEqual(preview.minY, 25 + 0.1 * 945, accuracy: 1)
    }

    func testPositionsOffTheScreenAreClampedInside() {
        for position in [BlockPosition(x: -3, y: 9), BlockPosition(x: 2, y: -1), BlockPosition(x: 1, y: 0), BlockPosition(x: 0, y: 1)] {
            let result = frames(preview: card, mainAt: position, previewAt: position)
            assertInside(result.main, screen)
            assertInside(try! XCTUnwrap(result.preview), screen)
        }
    }

    func testNonFinitePositionsAreIgnored() {
        let bad = BlockPosition(x: .nan, y: 0.5)
        XCTAssertFalse(bad.isValid)
        XCTAssertEqual(frames(preview: card, mainAt: bad, previewAt: bad).main, frames(preview: card).main)
        XCTAssertEqual(frames(preview: card, mainAt: bad, previewAt: bad).preview, frames(preview: card).preview)
    }

    func testBlocksLargerThanTheScreenAreShrunkToIt() {
        let small = ScreenRect(x: 0, y: 0, width: 300, height: 200)
        let result = frames(on: small)
        XCTAssertEqual(result.main, ScreenRect(x: 0, y: 0, width: 300, height: 200))
    }

    func testFramesOnASecondDisplay() {
        let right = ScreenRect(x: 1512, y: -200, width: 1920, height: 1055)
        let result = frames(preview: card, mainAt: BlockPosition(x: 0.5, y: 0.5), on: right)
        assertInside(result.main, right)
        assertInside(try! XCTUnwrap(result.preview), right)
        XCTAssertEqual(result.main.midX, right.midX, accuracy: 1)
    }

    // MARK: - Round trips

    func testRememberedPositionsRoundTrip() {
        let moved = ScreenRect(x: 200, y: 400, width: 640, height: 300)
        let position = PanelPlacement.mainPosition(of: moved, in: screen)
        XCTAssertEqual(frames(mainAt: position).main, moved)

        let card = ScreenRect(x: 900, y: 120, width: 420, height: 290)
        let cardPosition = PanelPlacement.previewPosition(of: card, in: screen)
        XCTAssertEqual(frames(preview: self.card, previewAt: cardPosition).preview, card)
    }

    func testPositionOfIsClampedAndSafe() {
        let p = PanelPlacement.mainPosition(of: ScreenRect(x: -500, y: 5000, width: 10, height: 10), in: screen)
        XCTAssertEqual(p, BlockPosition(x: 0, y: 1))
        XCTAssertEqual(PanelPlacement.mainPosition(of: ScreenRect(x: 0, y: 0, width: 1, height: 1), in: ScreenRect(x: 0, y: 0, width: 0, height: 0)),
                       BlockPosition(x: 0.5, y: 0.5))
    }

    func testClampKeepsWholePoints() {
        let clamped = PanelPlacement.clamp(ScreenRect(x: 10.4, y: 20.6, width: 100, height: 100), in: screen)
        XCTAssertEqual(clamped.x, 10)
        XCTAssertEqual(clamped.y, 25)
        let nan = PanelPlacement.clamp(ScreenRect(x: .nan, y: .infinity, width: 100, height: 100), in: screen)
        assertInside(nan, screen)
    }

    // MARK: - Decoding

    func testBlockPositionDecoding() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(BlockPosition.self, from: Data(#"{"x": 0.25, "y": 0.75}"#.utf8)), BlockPosition(x: 0.25, y: 0.75))
        XCTAssertThrowsError(try decoder.decode(BlockPosition.self, from: Data(#"{"x": "left", "y": 0.75}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(BlockPosition.self, from: Data(#"{"x": 0.5}"#.utf8)))
    }
}
