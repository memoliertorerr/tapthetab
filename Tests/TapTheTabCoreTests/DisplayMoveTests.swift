import XCTest
@testable import TapTheTabCore

final class DisplayMoveTests: XCTestCase {
    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ScreenRect {
        ScreenRect(x: x, y: y, width: width, height: height)
    }

    private func assertSane(_ result: ScreenRect, inside target: ScreenRect, file: StaticString = #filePath, line: UInt = #line) {
        for value in [result.x, result.y, result.width, result.height] {
            XCTAssertTrue(value.isFinite, "\(result)", file: file, line: line)
            XCTAssertEqual(value, value.rounded(), "whole points: \(result)", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(result.width, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(result.height, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(result.minX, target.minX, "\(result) in \(target)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(result.minY, target.minY, "\(result) in \(target)", file: file, line: line)
        XCTAssertLessThanOrEqual(result.maxX, target.maxX, "\(result) in \(target)", file: file, line: line)
        XCTAssertLessThanOrEqual(result.maxY, target.maxY, "\(result) in \(target)", file: file, line: line)
    }

    // MARK: - nextIndex

    func testNextIndexWraps() {
        XCTAssertEqual(DisplayMove.nextIndex(after: 0, count: 2), 1)
        XCTAssertEqual(DisplayMove.nextIndex(after: 1, count: 2), 0)
        XCTAssertEqual(DisplayMove.nextIndex(after: 0, count: 3), 1)
        XCTAssertEqual(DisplayMove.nextIndex(after: 1, count: 3), 2)
        XCTAssertEqual(DisplayMove.nextIndex(after: 2, count: 3), 0)
    }

    func testNextIndexNeedsTwoDisplays() {
        XCTAssertNil(DisplayMove.nextIndex(after: 0, count: 1))
        XCTAssertNil(DisplayMove.nextIndex(after: 0, count: 0))
        XCTAssertNil(DisplayMove.nextIndex(after: 0, count: -3))
    }

    func testNextIndexFromAnUnknownDisplayStartsAtTheFirst() {
        XCTAssertEqual(DisplayMove.nextIndex(after: -1, count: 2), 0)
        XCTAssertEqual(DisplayMove.nextIndex(after: 5, count: 3), 0)
        XCTAssertEqual(DisplayMove.nextIndex(after: Int.max, count: 2), 0)
    }

    // MARK: - displayIndex

    /// Main display, one to its left (negative x), one above it.
    private let displays = [
        ScreenRect(x: 0, y: 0, width: 1920, height: 1080),
        ScreenRect(x: -1440, y: 100, width: 1440, height: 900),
        ScreenRect(x: 0, y: 1080, width: 1920, height: 1080),
    ]

    func testDisplayIndexFindsTheHoldingDisplay() {
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(100, 100, 500, 500), displays: displays), 0)
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(-1000, 200, 500, 500), displays: displays), 1)
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(300, 1500, 500, 300), displays: displays), 2)
    }

    func testDisplayIndexPicksTheLargestOverlap() {
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(-200, 200, 500, 500), displays: displays), 0, "300 of 500 points on main")
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(-400, 200, 500, 500), displays: displays), 1, "400 of 500 points on the left")
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(100, 1000, 500, 300), displays: displays), 2, "220 of 300 points above")
    }

    func testDisplayIndexTieGoesToTheEarlierDisplay() {
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(-250, 200, 500, 500), displays: displays), 0)
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(-250, 200, 500, 500), displays: [displays[1], displays[0]]), 0)
    }

    func testDisplayIndexWithoutOverlapIsNil() {
        XCTAssertNil(DisplayMove.displayIndex(containing: rect(5000, 5000, 10, 10), displays: displays))
        XCTAssertNil(DisplayMove.displayIndex(containing: rect(1920, 0, 100, 100), displays: [displays[0]]), "touching an edge is not overlap")
        XCTAssertNil(DisplayMove.displayIndex(containing: rect(100, 100, 10, 10), displays: []))
    }

    func testDisplayIndexWithDegenerateInput() {
        XCTAssertNil(DisplayMove.displayIndex(containing: rect(100, 100, 0, 100), displays: displays))
        XCTAssertNil(DisplayMove.displayIndex(containing: rect(100, 100, -50, 100), displays: displays))
        XCTAssertNil(DisplayMove.displayIndex(containing: rect(.nan, 100, 50, 100), displays: displays))
        XCTAssertNil(DisplayMove.displayIndex(containing: rect(100, 100, .infinity, 100), displays: displays))
        let broken = [rect(.nan, 0, 1920, 1080), rect(0, 0, 0, 0), rect(0, 0, -1920, 1080), displays[0]]
        XCTAssertEqual(DisplayMove.displayIndex(containing: rect(100, 100, 500, 500), displays: broken), 3)
    }

    // MARK: - frame

    private let source = ScreenRect(x: 0, y: 0, width: 1000, height: 800)
    private let target = ScreenRect(x: 1000, y: 0, width: 2000, height: 1000)

    func testCentredWindowStaysCentred() {
        XCTAssertEqual(DisplayMove.frame(rect(250, 200, 500, 400), from: source, to: target), rect(1750, 300, 500, 400))
    }

    func testCornersStayInTheirCorners() {
        XCTAssertEqual(DisplayMove.frame(rect(0, 400, 500, 400), from: source, to: target), rect(1000, 600, 500, 400))
        XCTAssertEqual(DisplayMove.frame(rect(500, 0, 500, 400), from: source, to: target), rect(2500, 0, 500, 400))
        XCTAssertEqual(DisplayMove.frame(rect(0, 0, 500, 400), from: source, to: target), rect(1000, 0, 500, 400))
    }

    func testRelativePositionIsAFractionOfTheFreeSpace() {
        // 100 of 400 free points (25%) across; no free space down, so centred.
        XCTAssertEqual(DisplayMove.frame(rect(100, 0, 600, 800), from: source, to: target), rect(1350, 100, 600, 800))
    }

    func testSizeIsKeptWhenItFits() {
        let result = DisplayMove.frame(rect(37, 81, 640, 480), from: source, to: target)
        XCTAssertEqual(result.width, 640)
        XCTAssertEqual(result.height, 480)
        assertSane(result, inside: target)
    }

    func testLargerWindowShrinksToFit() {
        let left = rect(-1440, 200, 1440, 900)
        let big = rect(0, 0, 2560, 1440)
        let main = rect(0, 0, 2560, 1440)
        XCTAssertEqual(DisplayMove.frame(big, from: main, to: left), left)
    }

    func testShrinksOnlyTheAxisThatDoesNotFit() {
        let tall = rect(0, 0, 800, 1200)
        let result = DisplayMove.frame(tall, from: rect(0, 0, 1000, 1500), to: rect(1000, 0, 1600, 900))
        XCTAssertEqual(result, rect(1000, 0, 800, 900))
    }

    func testMoveToADisplayWithANegativeOrigin() {
        // Main (1920×1080) to a smaller monitor left of it.
        let result = DisplayMove.frame(rect(100, 100, 1200, 700), from: rect(0, 0, 1920, 1080), to: rect(-1280, 0, 1280, 800))
        XCTAssertEqual(result, rect(-1269, 26, 1200, 700))
    }

    func testMoveFromADisplayWithANegativeOrigin() {
        let result = DisplayMove.frame(rect(-1500, 300, 600, 400), from: rect(-1920, 0, 1920, 1080), to: rect(0, 0, 2560, 1440))
        XCTAssertEqual(result, rect(624, 459, 600, 400))
    }

    func testMoveToADisplayBelow() {
        // A display below the main one has a negative y in Cocoa coordinates.
        let below = rect(200, -900, 1600, 900)
        let result = DisplayMove.frame(rect(250, 200, 500, 400), from: source, to: below)
        XCTAssertEqual(result, rect(750, -650, 500, 400))
    }

    func testWindowPartlyOutsideItsDisplayLandsInside() {
        // Hanging off the right edge: treated as flush right.
        XCTAssertEqual(DisplayMove.frame(rect(900, 0, 400, 300), from: source, to: target), rect(2600, 0, 400, 300))
        // Hanging off the bottom-left: flush with those edges.
        XCTAssertEqual(DisplayMove.frame(rect(-100, -50, 400, 300), from: source, to: target), rect(1000, 0, 400, 300))
    }

    func testFractionalInputGivesWholePoints() {
        let result = DisplayMove.frame(rect(100.4, 50.6, 300.5, 200.4), from: rect(0, 0, 1000, 1000), to: rect(0, 0, 1000, 1000))
        XCTAssertEqual(result, rect(100, 51, 301, 200))
        let oddTarget = rect(10.25, 25.5, 999.5, 700.7)
        let fitted = DisplayMove.frame(rect(0, 0, 5000, 5000), from: source, to: oddTarget)
        assertSane(fitted, inside: oddTarget)
        XCTAssertEqual(fitted, rect(11, 26, 998, 700))
    }

    func testMovingToTheSameFrameKeepsAWholePointWindow() {
        let window = rect(123, 45, 678, 432)
        XCTAssertEqual(DisplayMove.frame(window, from: source, to: source), window)
    }

    func testMovingThereAndBackRestoresTheWindow() {
        let window = rect(200, 100, 400, 300)
        let there = DisplayMove.frame(window, from: source, to: target)
        XCTAssertEqual(DisplayMove.frame(there, from: target, to: source), window)
    }

    func testIndependentOfTheYDirection() {
        // Mirroring every rect vertically (y-down coordinates, like Accessibility) and
        // mirroring the result back gives the same frame.
        func mirrored(_ r: ScreenRect) -> ScreenRect { rect(r.x, -r.maxY, r.width, r.height) }
        let cases: [(ScreenRect, ScreenRect, ScreenRect)] = [
            (rect(250, 100, 500, 300), source, rect(1000, -200, 2000, 1000)),
            (rect(-1500, 300, 600, 400), rect(-1920, 0, 1920, 1080), rect(0, 0, 2560, 1440)),
            (rect(0, 0, 800, 1200), rect(0, 0, 1000, 1500), rect(1000, 0, 1600, 900)),
            (rect(10, 700, 300, 90), source, rect(0, 800, 1280, 1024)),
        ]
        for (window, from, to) in cases {
            let direct = DisplayMove.frame(window, from: from, to: to)
            let viaMirror = mirrored(DisplayMove.frame(mirrored(window), from: mirrored(from), to: mirrored(to)))
            XCTAssertEqual(viaMirror, direct, "\(window)")
        }
    }

    // MARK: - Degenerate input

    func testUnusableTargetLeavesTheWindowAlone() {
        let window = rect(100, 100, 400, 300)
        for bad in [rect(0, 0, 0, 0), rect(0, 0, -100, 800), rect(0, 0, 800, 0), rect(.nan, 0, 800, 600),
                    rect(0, 0, .infinity, 600), rect(0, .nan, 800, 600), rect(0, 0, 800, .nan)] {
            XCTAssertEqual(DisplayMove.frame(window, from: source, to: bad), window, "\(bad)")
        }
    }

    func testUnusableSourceCentresTheWindow() {
        for bad in [rect(0, 0, 0, 0), rect(0, 0, -1000, 800), rect(.nan, 0, 1000, 800), rect(0, 0, .infinity, 800)] {
            XCTAssertEqual(DisplayMove.frame(rect(10, 10, 200, 100), from: bad, to: rect(0, 0, 1000, 800)), rect(400, 350, 200, 100), "\(bad)")
        }
    }

    func testWindowWithoutUsableSize() {
        let display = rect(0, 0, 1000, 800)
        XCTAssertEqual(DisplayMove.frame(rect(10, 10, 0, 0), from: source, to: display), rect(500, 400, 1, 1))
        XCTAssertEqual(DisplayMove.frame(rect(10, 10, -50, .nan), from: source, to: display), rect(500, 400, 1, 1))
        XCTAssertEqual(DisplayMove.frame(rect(10, 10, .infinity, 100), from: source, to: display), rect(0, 10, 1000, 100), "y keeps its place")
        XCTAssertEqual(DisplayMove.frame(rect(.nan, .nan, 200, 100), from: source, to: display), rect(400, 350, 200, 100))
        XCTAssertEqual(DisplayMove.frame(rect(-.infinity, .infinity, 200, 100), from: source, to: display), rect(400, 350, 200, 100))
    }

    func testTinyTargetNeverProducesNaN() {
        let result = DisplayMove.frame(rect(0, 0, 300, 200), from: source, to: rect(10.2, 10.2, 0.5, 0.5))
        for value in [result.x, result.y, result.width, result.height] {
            XCTAssertTrue(value.isFinite)
        }
    }

    func testResultIsAlwaysInsideTheTarget() {
        let windows = [rect(0, 0, 100, 100), rect(-500, -500, 3000, 200), rect(950, 750, 300, 300),
                       rect(333.3, 222.2, 444.4, 111.1), rect(0, 0, 1000, 800), rect(-10, 900, 20, 20)]
        let frames = [source, target, rect(-1440, 100, 1440, 900), rect(0, 1080, 1920, 1080),
                      rect(-3000.5, -200.25, 800.75, 600.5), rect(5, 5, 50, 40)]
        for window in windows {
            for from in frames {
                for to in frames {
                    assertSane(DisplayMove.frame(window, from: from, to: to), inside: to)
                }
            }
        }
    }
}
