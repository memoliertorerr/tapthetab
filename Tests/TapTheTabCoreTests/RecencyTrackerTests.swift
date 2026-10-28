import XCTest
@testable import TapTheTabCore

final class RecencyTrackerTests: XCTestCase {
    private let items = (1...5).map { window(UInt32($0)) }

    private func ids(_ items: [SwitcherItem]) -> [ItemID] { items.map(\.id) }

    func testEmptyTrackerKeepsInputOrder() {
        let tracker = RecencyTracker()
        XCTAssertEqual(tracker.ordered(items), items)
        XCTAssertEqual(tracker.trackedCount, 0)
    }

    func testMostRecentlyTouchedFirst() {
        var tracker = RecencyTracker()
        tracker.touch(.window(2))
        tracker.touch(.window(4))
        tracker.touch(.window(3))
        XCTAssertEqual(ids(tracker.ordered(items)), [.window(3), .window(4), .window(2), .window(1), .window(5)])
    }

    func testTouchingAgainMovesToFront() {
        var tracker = RecencyTracker()
        tracker.touch(.window(1))
        tracker.touch(.window(2))
        tracker.touch(.window(1))
        XCTAssertEqual(ids(tracker.ordered(items)).prefix(2), [.window(1), .window(2)])
        XCTAssertEqual(tracker.trackedCount, 2)
    }

    func testUntrackedKeepInputOrderAfterTracked() {
        var tracker = RecencyTracker()
        tracker.touch(.window(5))
        let shuffled = [items[3], items[0], items[4], items[2], items[1]]
        XCTAssertEqual(ids(tracker.ordered(shuffled)), [.window(5), .window(4), .window(1), .window(3), .window(2)])
    }

    func testStampsIncrease() throws {
        var tracker = RecencyTracker()
        XCTAssertNil(tracker.stamp(for: .window(1)))
        tracker.touch(.window(1))
        tracker.touch(.window(2))
        let a = try XCTUnwrap(tracker.stamp(for: .window(1)))
        let b = try XCTUnwrap(tracker.stamp(for: .window(2)))
        XCTAssertLessThan(a, b)
    }

    func testForget() {
        var tracker = RecencyTracker()
        tracker.touch(.window(3))
        tracker.touch(.window(1))
        tracker.forget(.window(1))
        XCTAssertNil(tracker.stamp(for: .window(1)))
        XCTAssertEqual(tracker.trackedCount, 1)
        XCTAssertEqual(ids(tracker.ordered(items)), [.window(3), .window(1), .window(2), .window(4), .window(5)])
    }

    func testForgetUnknownIsNoOp() {
        var tracker = RecencyTracker()
        tracker.touch(.window(1))
        let before = tracker
        tracker.forget(.window(99))
        XCTAssertEqual(tracker, before)
    }

    func testPruneKeepsOnlyAliveItems() {
        var tracker = RecencyTracker()
        tracker.touch(.window(1))
        tracker.touch(.window(2))
        tracker.touch(.app(pid: 7))
        tracker.prune(keeping: [.window(2), .window(9)])
        XCTAssertEqual(tracker.trackedCount, 1)
        XCTAssertNotNil(tracker.stamp(for: .window(2)))
        XCTAssertNil(tracker.stamp(for: .window(1)))
        XCTAssertNil(tracker.stamp(for: .app(pid: 7)))
    }

    func testPruneWithEmptySetClearsEverything() {
        var tracker = RecencyTracker()
        tracker.touch(.window(1))
        tracker.prune(keeping: [])
        XCTAssertEqual(tracker.trackedCount, 0)
    }

    func testWindowAndAppIDsAreDistinct() {
        var tracker = RecencyTracker()
        tracker.touch(.app(pid: 1))
        XCTAssertNil(tracker.stamp(for: .window(1)))
        let mixed = [window(1, pid: 1), windowlessApp(pid: 1)]
        XCTAssertEqual(ids(tracker.ordered(mixed)), [.app(pid: 1), .window(1)])
    }

    func testOrderedDoesNotDropOrDuplicate() {
        var tracker = RecencyTracker()
        tracker.touch(.window(42)) // not in the list
        tracker.touch(.window(2))
        let result = tracker.ordered(items)
        XCTAssertEqual(result.count, items.count)
        XCTAssertEqual(Set(ids(result)), Set(ids(items)))
    }
}
