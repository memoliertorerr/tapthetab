import XCTest
@testable import TapTheTabCore

final class ItemOrderingTests: XCTestCase {
    private func ids(_ items: [SwitcherItem]) -> [ItemID] { items.map(\.id) }

    // MARK: - groupedByApp

    func testGroupsAppsByMostRecentWindow() {
        // Recency order: Safari 1, Mail 2, Safari 3, Notes 4, Mail 5, Safari 6.
        let items = [
            window(1, pid: 10, app: "Safari"),
            window(2, pid: 20, app: "Mail"),
            window(3, pid: 10, app: "Safari"),
            window(4, pid: 30, app: "Notes"),
            window(5, pid: 20, app: "Mail"),
            window(6, pid: 10, app: "Safari"),
        ]
        XCTAssertEqual(ids(ItemOrdering.groupedByApp(items)),
                       [.window(1), .window(3), .window(6), .window(2), .window(5), .window(4)])
    }

    func testWindowsKeepTheirOrderWithinAnApp() {
        let items = [
            window(9, pid: 1), window(3, pid: 2), window(7, pid: 1), window(1, pid: 1), window(5, pid: 2),
        ]
        let grouped = ItemOrdering.groupedByApp(items)
        XCTAssertEqual(ids(grouped.filter { $0.pid == 1 }), [.window(9), .window(7), .window(1)])
        XCTAssertEqual(ids(grouped.filter { $0.pid == 2 }), [.window(3), .window(5)])
    }

    func testFirstItemStaysFirst() {
        let items = [window(1, pid: 1), window(2, pid: 2), window(3, pid: 3), window(4, pid: 1)]
        XCTAssertEqual(ItemOrdering.groupedByApp(items).first?.id, .window(1))
    }

    func testNothingAddedOrDropped() {
        let items = (0..<40).map { window(UInt32($0), pid: Int32($0 % 7)) }
        let grouped = ItemOrdering.groupedByApp(items)
        XCTAssertEqual(grouped.count, items.count)
        XCTAssertEqual(Set(ids(grouped)), Set(ids(items)))
    }

    func testAppsAreContiguous() {
        let items = (0..<40).map { window(UInt32($0), pid: Int32(($0 * 5) % 6)) }
        let grouped = ItemOrdering.groupedByApp(items)
        var seen: [Int32] = []
        for item in grouped where item.pid != seen.last {
            XCTAssertFalse(seen.contains(item.pid), "pid \(item.pid) appears in two runs")
            seen.append(item.pid)
        }
    }

    func testAlreadyGroupedIsUnchanged() {
        let items = [window(1, pid: 1), window(2, pid: 1), window(3, pid: 2), window(4, pid: 3), window(5, pid: 3)]
        XCTAssertEqual(ItemOrdering.groupedByApp(items), items)
    }

    func testIdempotent() {
        let items = [window(1, pid: 1), window(2, pid: 2), window(3, pid: 1), window(4, pid: 3), window(5, pid: 2)]
        let once = ItemOrdering.groupedByApp(items)
        XCTAssertEqual(ItemOrdering.groupedByApp(once), once)
    }

    func testTrivialInputs() {
        XCTAssertEqual(ItemOrdering.groupedByApp([]), [])
        let one = [window(1)]
        XCTAssertEqual(ItemOrdering.groupedByApp(one), one)
        let singleApp = [window(3, pid: 5), window(1, pid: 5), window(2, pid: 5)]
        XCTAssertEqual(ItemOrdering.groupedByApp(singleApp), singleApp)
        let onePerApp = [window(1, pid: 3), window(2, pid: 1), window(3, pid: 2)]
        XCTAssertEqual(ItemOrdering.groupedByApp(onePerApp), onePerApp)
    }

    func testTwoCopiesOfAnAppAreSeparateGroups() {
        // Same bundle and name, different processes.
        let items = [
            window(1, pid: 10, app: "Editor", bundle: "com.example.editor"),
            window(2, pid: 11, app: "Editor", bundle: "com.example.editor"),
            window(3, pid: 10, app: "Editor", bundle: "com.example.editor"),
        ]
        XCTAssertEqual(ids(ItemOrdering.groupedByApp(items)), [.window(1), .window(3), .window(2)])
    }

    func testWindowlessAppsTakeTheirRecencyPlace() {
        let items = [window(1, pid: 1), windowlessApp(pid: 9), window(2, pid: 2), window(3, pid: 1)]
        XCTAssertEqual(ids(ItemOrdering.groupedByApp(items)), [.window(1), .window(3), .app(pid: 9), .window(2)])
    }

    func testGroupingAfterFiltersKeepsFilteredItemsOut() {
        let items = [
            window(1, pid: 1, bundle: "com.a"),
            window(2, pid: 2, bundle: "com.excluded"),
            window(3, pid: 1, bundle: "com.a", minimized: true),
            window(4, pid: 3, bundle: "com.c"),
            window(5, pid: 1, bundle: "com.a"),
        ]
        var options = FilterOptions()
        options.showMinimized = false
        options.excludedBundleIDs = ["com.excluded"]
        let filtered = ItemFilter.apply(items, options: options, scope: .allWindows, context: FilterContext())
        XCTAssertEqual(ids(ItemOrdering.groupedByApp(filtered)), [.window(1), .window(5), .window(4)])
    }

    func testGroupingIsANoOpForSingleAppAndAppsScopes() {
        let items = [window(1, pid: 1), window(2, pid: 2), window(3, pid: 1), window(4, pid: 3)]
        for scope in [SwitcherScope.activeApp, .apps] {
            let filtered = ItemFilter.apply(items, options: FilterOptions(), scope: scope, context: FilterContext(activePID: 1))
            XCTAssertEqual(ItemOrdering.groupedByApp(filtered), filtered, "\(scope)")
        }
    }

    func testSessionStartsOnTheSecondGroupedItem() {
        // The session sees the grouped order: a tap goes to the next item shown, which is
        // the frontmost app's other window when it has one.
        let items = [window(1, pid: 1), window(2, pid: 2), window(3, pid: 1)]
        let session = SwitcherSession(items: ItemOrdering.groupedByApp(items))
        XCTAssertEqual(session.selectedItem?.id, .window(3))
    }

    func testSearchStillRanksByScore() {
        let items = [
            window(1, pid: 1, app: "Safari", title: "News"),
            window(2, pid: 2, app: "Mail", title: "Inbox"),
            window(3, pid: 1, app: "Safari", title: "Docs"),
            window(4, pid: 2, app: "Mail", title: "Draft: notes"),
        ]
        var session = SwitcherSession(items: ItemOrdering.groupedByApp(items))
        XCTAssertEqual(session.visible.map(\.id), [.window(1), .window(3), .window(2), .window(4)])
        session.handle(.type("inbox"))
        XCTAssertEqual(session.visible.first?.id, .window(2))
        session.handle(.cancel)
        XCTAssertEqual(session.visible.map(\.id), [.window(1), .window(3), .window(2), .window(4)], "grouped again without a query")
    }

    // MARK: - sectionHeaderIndices

    private let mixed = [
        window(1, pid: 1, app: "Safari"), window(2, pid: 1, app: "Safari"),
        window(3, pid: 2, app: "Mail"),
        window(4, pid: 3, app: "Notes"), window(5, pid: 3, app: "Notes"), window(6, pid: 3, app: "Notes"),
    ]

    private func headers(_ items: [SwitcherItem], groupByApp: Bool = true, style: LayoutStyle = .list, searching: Bool = false) -> [Int] {
        ItemOrdering.sectionHeaderIndices(for: items, groupByApp: groupByApp, style: style, isSearching: searching)
    }

    func testHeadersAtTheFirstItemOfEachApp() {
        XCTAssertEqual(headers(mixed), [0, 2, 3])
    }

    func testNoHeadersWhenGroupingIsOff() {
        XCTAssertEqual(headers(mixed, groupByApp: false), [])
    }

    func testNoHeadersInTheGrid() {
        XCTAssertEqual(headers(mixed, style: .grid), [])
    }

    func testNoHeadersWhileSearching() {
        XCTAssertEqual(headers(mixed, searching: true), [])
    }

    func testNoHeadersForOneApp() {
        XCTAssertEqual(headers([window(1, pid: 1), window(2, pid: 1), window(3, pid: 1)]), [])
    }

    func testNoHeadersWhenEveryAppHasOneItem() {
        // Like the "apps" scope: each row already shows its app.
        XCTAssertEqual(headers([window(1, pid: 1), window(2, pid: 2), window(3, pid: 3)]), [])
    }

    func testNoHeadersForTinyLists() {
        XCTAssertEqual(headers([]), [])
        XCTAssertEqual(headers([window(1)]), [])
    }

    func testOneMultiWindowAppIsEnoughForHeaders() {
        XCTAssertEqual(headers([window(1, pid: 1), window(2, pid: 1), window(3, pid: 2)]), [0, 2])
    }

    func testHeadersFollowRunsNotApps() {
        // Ungrouped input (for example after an optimistic update): a heading per run.
        XCTAssertEqual(headers([window(1, pid: 1), window(2, pid: 1), window(3, pid: 2), window(4, pid: 1)]), [0, 2, 3])
    }

    func testHeaderCountFeedsTheListLayout() {
        let grouped = ItemOrdering.groupedByApp(mixed)
        let starts = headers(grouped)
        let layout = PanelLayout.compute(style: .list, size: .medium, itemCount: grouped.count, showsSearchBar: true,
                                         screenSize: Size(width: 1512, height: 945), sectionHeaderCount: starts.count)
        XCTAssertEqual(layout.panelSize.height, 396, "44 + 6 × 44 + 3 × 24 + 16")
    }
}
