import XCTest
@testable import TapTheTabCore

final class SwitcherSessionTests: XCTestCase {
    /// Five windows: Safari, Terminal, Mail, Notes, Xcode (in recency order).
    private let items: [SwitcherItem] = [
        window(1, pid: 1, app: "Safari", title: "Apple"),
        window(2, pid: 2, app: "Terminal", title: "zsh"),
        window(3, pid: 3, app: "Mail", title: "Inbox"),
        window(4, pid: 4, app: "Notes", title: "Shopping list"),
        window(5, pid: 5, app: "Xcode", title: "TapTheTab"),
    ]

    private func session(_ items: [SwitcherItem]? = nil, columns: Int = 1, wraps: Bool = true, startsOnPrevious: Bool = true, locked: Bool = false) -> SwitcherSession {
        SwitcherSession(items: items ?? self.items, startsOnPrevious: startsOnPrevious, locked: locked, columns: columns, wrapsAround: wraps)
    }

    private func grid(count: Int, columns: Int, wraps: Bool = true) -> SwitcherSession {
        SwitcherSession(items: (0..<count).map { window(UInt32($0)) }, columns: columns, wrapsAround: wraps)
    }

    // MARK: - Opening

    func testStartsOnPreviousSelectsSecondItem() {
        let s = session()
        XCTAssertEqual(s.selectedIndex, 1)
        XCTAssertEqual(s.selectedItem?.id, .window(2))
        XCTAssertEqual(s.visible.map(\.id), items.map(\.id))
        XCTAssertFalse(s.isSearching)
        XCTAssertFalse(s.isLocked)
    }

    func testSingleItemSelectsFirst() {
        XCTAssertEqual(session([items[0]]).selectedIndex, 0)
    }

    func testEmptyHasNoSelection() {
        let s = session([])
        XCTAssertNil(s.selectedIndex)
        XCTAssertNil(s.selectedItem)
    }

    func testWithoutStartsOnPreviousSelectsFirst() {
        XCTAssertEqual(session(startsOnPrevious: false).selectedIndex, 0)
    }

    func testColumnsAreAtLeastOne() {
        var s = session(columns: 0)
        XCTAssertEqual(s.columns, 1)
        s.columns = -3
        XCTAssertEqual(s.columns, 1)
        s.columns = 4
        XCTAssertEqual(s.columns, 4)
    }

    func testVisibleItemsHaveNoMatchWithoutQuery() {
        XCTAssertTrue(session().visible.allSatisfy { $0.match == nil })
    }

    // MARK: - Linear navigation

    func testNextAndPreviousWrap() {
        var s = session()
        XCTAssertEqual(s.handle(.next), .refresh)
        XCTAssertEqual(s.selectedIndex, 2)
        s.handle(.last)
        XCTAssertEqual(s.selectedIndex, 4)
        s.handle(.next)
        XCTAssertEqual(s.selectedIndex, 0)
        s.handle(.previous)
        XCTAssertEqual(s.selectedIndex, 4)
    }

    func testNoWrapClampsAtEnds() {
        var s = session(wraps: false)
        s.handle(.first)
        XCTAssertEqual(s.handle(.previous), .none)
        XCTAssertEqual(s.selectedIndex, 0)
        s.handle(.last)
        XCTAssertEqual(s.handle(.next), .none)
        XCTAssertEqual(s.selectedIndex, 4)
    }

    func testLeftRightStepLinearly() {
        var s = session(columns: 3)
        s.handle(.moveRight)
        XCTAssertEqual(s.selectedIndex, 2)
        s.handle(.moveRight)
        XCTAssertEqual(s.selectedIndex, 3, "moving right continues onto the next row")
        s.handle(.moveLeft)
        XCTAssertEqual(s.selectedIndex, 2)
    }

    func testUpDownInListStepByOne() {
        var s = session()
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 2)
        s.handle(.moveUp)
        s.handle(.moveUp)
        XCTAssertEqual(s.selectedIndex, 0)
    }

    func testFirstLastAndSelect() {
        var s = session()
        XCTAssertEqual(s.handle(.first), .refresh)
        XCTAssertEqual(s.selectedIndex, 0)
        XCTAssertEqual(s.handle(.first), .none, "re-selecting the same index changes nothing")
        XCTAssertEqual(s.handle(.last), .refresh)
        XCTAssertEqual(s.selectedIndex, 4)
        XCTAssertEqual(s.handle(.select(index: 3)), .refresh)
        XCTAssertEqual(s.selectedIndex, 3)
        XCTAssertEqual(s.handle(.select(index: 99)), .none)
        XCTAssertEqual(s.handle(.select(index: -1)), .none)
        XCTAssertEqual(s.selectedIndex, 3)
    }

    func testNavigationOnEmptyIsNoOp() {
        var s = session([])
        for input: SwitcherInput in [.next, .previous, .moveUp, .moveDown, .moveLeft, .moveRight, .first, .last] {
            XCTAssertEqual(s.handle(input), .none, "\(input)")
        }
        XCTAssertNil(s.selectedIndex)
    }

    func testNextOnSingleItemIsNoOp() {
        var s = session([items[0]])
        XCTAssertEqual(s.handle(.next), .none)
        XCTAssertEqual(s.selectedIndex, 0)
    }

    // MARK: - Grid navigation

    func testGridDownAndUpMoveByRow() {
        var s = grid(count: 9, columns: 3)
        s.handle(.select(index: 1))
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 4)
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 7)
        s.handle(.moveUp)
        XCTAssertEqual(s.selectedIndex, 4)
    }

    func testGridDownWrapsToSameColumnOnFirstRow() {
        var s = grid(count: 9, columns: 3)
        s.handle(.select(index: 8))
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 2)
    }

    func testGridUpWrapsToSameColumnOnLastRow() {
        var s = grid(count: 9, columns: 3)
        s.handle(.select(index: 0))
        s.handle(.moveUp)
        XCTAssertEqual(s.selectedIndex, 6)
    }

    func testGridUpWrapIntoPartialLastRowClampsToLastItem() {
        // 7 items in 3 columns: rows [0 1 2] [3 4 5] [6].
        var s = grid(count: 7, columns: 3)
        s.handle(.select(index: 2))
        s.handle(.moveUp)
        XCTAssertEqual(s.selectedIndex, 6)
        s.handle(.select(index: 0))
        s.handle(.moveUp)
        XCTAssertEqual(s.selectedIndex, 6)
    }

    func testGridDownFromAboveGapInPartialRowLandsOnLastItem() {
        // 7 items in 3 columns: rows [0 1 2] [3 4 5] [6]. Index 5 has no cell below it,
        // but a lower row exists, so ↓ goes to the last item instead of wrapping (Finder).
        var s = grid(count: 7, columns: 3)
        s.handle(.select(index: 5))
        XCTAssertEqual(s.handle(.moveDown), .refresh)
        XCTAssertEqual(s.selectedIndex, 6)
        s.handle(.select(index: 4))
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 6)
    }

    func testGridDownFromAboveGapLandsOnLastItemWithoutWrap() {
        // Landing on the last item is not a wrap, so it also happens with wrapping off.
        var s = grid(count: 8, columns: 3, wraps: false)
        s.handle(.select(index: 5))
        XCTAssertEqual(s.handle(.moveDown), .refresh)
        XCTAssertEqual(s.selectedIndex, 7)
        XCTAssertEqual(s.handle(.moveDown), .none, "already on the last row")
        XCTAssertEqual(s.selectedIndex, 7)
    }

    func testGridDownColumnWithCellBelowStillMovesStraightDown() {
        var s = grid(count: 8, columns: 3)
        s.handle(.select(index: 3))
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 6)
        s.handle(.select(index: 4))
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 7)
    }

    func testGridDownFromLastRowWrapsToItsColumnOnFirstRow() {
        var s = grid(count: 7, columns: 3)
        s.handle(.select(index: 6))
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 0)

        var t = grid(count: 8, columns: 3)
        t.handle(.select(index: 7))
        t.handle(.moveDown)
        XCTAssertEqual(t.selectedIndex, 1)
    }

    func testGridDownThenUpFromGapReturnsToTheRowAbove() {
        // ↓ from 5 lands on 6; ↑ from 6 goes straight up to 3 (↑ never needs a gap rule:
        // every row above the last one is full).
        var s = grid(count: 7, columns: 3)
        s.handle(.select(index: 5))
        s.handle(.moveDown)
        s.handle(.moveUp)
        XCTAssertEqual(s.selectedIndex, 3)
    }

    func testGridDownInSingleRowWraps() {
        var s = grid(count: 3, columns: 4)
        s.handle(.select(index: 2))
        XCTAssertEqual(s.handle(.moveDown), .none, "single row: wrapping lands on the same cell")
        XCTAssertEqual(s.selectedIndex, 2)
    }

    func testGridWithoutWrapStopsAtEdges() {
        var s = grid(count: 9, columns: 3, wraps: false)
        s.handle(.select(index: 7))
        XCTAssertEqual(s.handle(.moveDown), .none)
        XCTAssertEqual(s.selectedIndex, 7)
        s.handle(.select(index: 1))
        XCTAssertEqual(s.handle(.moveUp), .none)
        XCTAssertEqual(s.selectedIndex, 1)
    }

    func testGridColumnsChangeAfterInit() {
        var s = grid(count: 8, columns: 1)
        s.columns = 4
        s.handle(.select(index: 1))
        s.handle(.moveDown)
        XCTAssertEqual(s.selectedIndex, 5)
    }

    // MARK: - Search

    func testTypingFiltersAndSelectsBestMatch() {
        var s = session()
        XCTAssertEqual(s.handle(.type("no")), .refresh)
        XCTAssertEqual(s.query, "no")
        XCTAssertTrue(s.isSearching)
        XCTAssertEqual(s.selectedIndex, 0)
        XCTAssertEqual(s.selectedItem?.appName, "Notes")
        XCTAssertTrue(s.visible.allSatisfy { $0.match != nil })
    }

    func testTypingRanksByScoreThenOriginalOrder() {
        let list = [
            window(1, app: "Editor", title: "report draft"),
            window(2, app: "Editor", title: "port"),
            window(3, app: "Editor", title: "Unrelated"),
        ]
        var s = session(list)
        s.handle(.type("port"))
        XCTAssertEqual(s.visible.map(\.id), [.window(2), .window(1)])
    }

    func testEqualScoresKeepOriginalOrder() {
        let list = [window(1, app: "A", title: "same"), window(2, app: "A", title: "same"), window(3, app: "A", title: "same")]
        var s = session(list)
        s.handle(.type("same"))
        XCTAssertEqual(s.visible.map(\.id), [.window(1), .window(2), .window(3)])
    }

    func testTypingWithNoMatchesClearsSelection() {
        var s = session()
        s.handle(.type("qqqq"))
        XCTAssertTrue(s.visible.isEmpty)
        XCTAssertNil(s.selectedIndex)
        XCTAssertEqual(s.handle(.commit), .dismiss)
        XCTAssertEqual(s.handle(.triggerReleased), .dismiss)
    }

    func testLeadingSpaceIsIgnored() {
        var s = session()
        XCTAssertEqual(s.handle(.type(" ")), .none)
        XCTAssertEqual(s.query, "")
    }

    func testSpaceInsideQueryIsKept() {
        var s = session()
        s.handle(.type("shop"))
        XCTAssertEqual(s.handle(.type(" ")), .refresh)
        s.handle(.type("li"))
        XCTAssertEqual(s.query, "shop li")
        XCTAssertEqual(s.selectedItem?.appName, "Notes")
    }

    func testNewlinesAndTabsAreStripped() {
        var s = session()
        XCTAssertEqual(s.handle(.type("\n\t")), .none)
        s.handle(.type("ma\til\n"))
        XCTAssertEqual(s.query, "mail")
    }

    func testDeleteBackwardRestoresList() {
        var s = session()
        s.handle(.type("x"))
        s.handle(.type("c"))
        XCTAssertEqual(s.visible.map(\.id), [.window(5)])
        XCTAssertEqual(s.handle(.deleteBackward), .refresh)
        XCTAssertEqual(s.query, "x")
        XCTAssertEqual(s.handle(.deleteBackward), .refresh)
        XCTAssertEqual(s.query, "")
        XCTAssertEqual(s.visible.map(\.id), items.map(\.id))
        XCTAssertEqual(s.selectedIndex, 1, "an empty query restores the open-time selection")
    }

    func testDeleteBackwardKeepsSelectedItemWhileSearching() {
        let list = [
            window(1, app: "Ed", title: "alpha"),
            window(2, app: "Ed", title: "alpine"),
            window(3, app: "Ed", title: "albatross"),
        ]
        var s = session(list)
        s.handle(.type("al"))
        XCTAssertEqual(s.visible.map(\.id), [.window(1), .window(2), .window(3)])
        s.handle(.type("b"))
        XCTAssertEqual(s.visible.map(\.id), [.window(3)])
        s.handle(.deleteBackward)
        XCTAssertEqual(s.query, "al")
        XCTAssertEqual(s.selectedItem?.id, .window(3), "selection follows the item, not the position")
        XCTAssertEqual(s.selectedIndex, 2)
    }

    func testDeleteBackwardOnEmptyQueryIsNoOp() {
        var s = session()
        XCTAssertEqual(s.handle(.deleteBackward), .none)
    }

    // MARK: - Search memory

    private let slackAndSafari: [SwitcherItem] = [
        window(1, pid: 1, app: "Safari", bundle: "com.apple.Safari", title: "Apple"),
        window(2, pid: 2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "general"),
        window(3, pid: 3, app: "Mail", bundle: "com.apple.mail", title: "Inbox"),
    ]

    func testSessionStartsWithEmptySearchMemoryByDefault() {
        XCTAssertTrue(session().searchMemory.isEmpty)
    }

    func testSearchMemoryReordersCloseMatches() {
        var plain = session(slackAndSafari)
        plain.handle(.type("s"))
        XCTAssertEqual(plain.visible.map(\.id), [.window(1), .window(2)], "equal scores keep recency order")

        var memory = SearchMemory()
        memory.record(query: "sl", picked: slackAndSafari[1])
        var s = SwitcherSession(items: slackAndSafari, searchMemory: memory)
        XCTAssertEqual(s.searchMemory, memory)
        s.handle(.type("s"))
        XCTAssertEqual(s.visible.map(\.id), [.window(2), .window(1)], "Slack was picked for \"sl\"")
        XCTAssertEqual(s.selectedItem?.id, .window(2))
        s.handle(.type("l"))
        XCTAssertEqual(s.selectedItem?.id, .window(2))
    }

    func testSearchMemoryKeepsRawMatchScores() throws {
        var memory = SearchMemory()
        memory.record(query: "s", picked: slackAndSafari[1])
        var plain = session(slackAndSafari)
        var boosted = SwitcherSession(items: slackAndSafari, searchMemory: memory)
        plain.handle(.type("s"))
        boosted.handle(.type("s"))
        let a = try XCTUnwrap(plain.visible.first { $0.id == .window(2) })
        let b = try XCTUnwrap(boosted.visible.first { $0.id == .window(2) })
        XCTAssertEqual(a.match, b.match, "the boost changes order only, not FuzzyMatch")
    }

    func testSearchMemoryNeverAddsNonMatchingItems() {
        var memory = SearchMemory()
        for _ in 0..<10 { memory.record(query: "s", picked: slackAndSafari[2]) } // Mail, for "s"
        var s = SwitcherSession(items: slackAndSafari, searchMemory: memory)
        s.handle(.type("s"))
        XCTAssertFalse(s.visible.contains { $0.id == .window(3) }, "\"Mail\"/\"Inbox\" does not match \"s\"")
        XCTAssertEqual(Set(s.visible.map(\.id)), [.window(1), .window(2)])
    }

    func testSearchMemoryDoesNotChangeEmptyQueryOrder() {
        var memory = SearchMemory()
        memory.record(query: "mail", picked: slackAndSafari[2])
        var s = SwitcherSession(items: slackAndSafari, searchMemory: memory)
        XCTAssertEqual(s.visible.map(\.id), slackAndSafari.map(\.id))
        XCTAssertEqual(s.selectedIndex, 1)
        s.handle(.type("m"))
        s.handle(.deleteBackward)
        XCTAssertEqual(s.visible.map(\.id), slackAndSafari.map(\.id))
        XCTAssertEqual(s.selectedIndex, 1)
    }

    func testSearchMemoryDoesNotOverrideStrongMatchAfterOnePick() {
        // A scattered subsequence hit stays below a strong contiguous prefix hit.
        let list = [
            window(1, pid: 1, app: "Terminal", title: "zsh"),
            window(2, pid: 2, app: "Notes", title: "the error message"),
        ]
        var memory = SearchMemory()
        memory.record(query: "term", picked: list[1])
        var s = SwitcherSession(items: list, searchMemory: memory)
        s.handle(.type("term"))
        XCTAssertEqual(s.visible.map(\.id), [.window(1), .window(2)])
    }

    func testSearchMemoryPrefersPickedWindowOverSiblingOfSameApp() {
        let list = [
            window(1, pid: 1, app: "Code", bundle: "com.microsoft.VSCode", title: "server.swift"),
            window(2, pid: 1, app: "Code", bundle: "com.microsoft.VSCode", title: "client.swift"),
        ]
        var memory = SearchMemory()
        memory.record(query: "swift", picked: list[1])
        var s = SwitcherSession(items: list, searchMemory: memory)
        s.handle(.type("swift"))
        XCTAssertEqual(s.visible.map(\.id), [.window(2), .window(1)])
    }

    func testSearchMemorySurvivesReplaceItems() {
        var memory = SearchMemory()
        memory.record(query: "s", picked: slackAndSafari[1])
        var s = SwitcherSession(items: slackAndSafari, searchMemory: memory)
        s.handle(.type("s"))
        s.replaceItems(slackAndSafari + [window(4, pid: 4, app: "Stocks", title: "")])
        XCTAssertEqual(s.searchMemory, memory)
        XCTAssertEqual(s.visible.first?.id, .window(2))
    }

    func testSearchMemoryUsesAppIdentityForNewWindows() {
        // The window Slack was picked in is gone; Slack's new window still benefits.
        var memory = SearchMemory()
        memory.record(query: "s", picked: window(99, pid: 2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "old"))
        var s = SwitcherSession(items: slackAndSafari, searchMemory: memory)
        s.handle(.type("s"))
        XCTAssertEqual(s.visible.first?.id, .window(2))
    }

    // MARK: - Cancel / commit / release

    func testCancelClearsQueryFirstThenDismisses() {
        var s = session()
        s.handle(.type("mail"))
        XCTAssertEqual(s.handle(.cancel), .refresh)
        XCTAssertEqual(s.query, "")
        XCTAssertEqual(s.visible.count, items.count)
        XCTAssertEqual(s.handle(.cancel), .dismiss)
    }

    func testCommitActivatesSelection() {
        var s = session()
        XCTAssertEqual(s.handle(.commit), .activate(items[1]))
    }

    func testCommitWithNoItemsDismisses() {
        var s = session([])
        XCTAssertEqual(s.handle(.commit), .dismiss)
    }

    func testTriggerReleasedActivatesWhenUnlocked() {
        var s = session()
        s.handle(.next)
        XCTAssertEqual(s.handle(.triggerReleased), .activate(items[2]))
    }

    func testTriggerReleasedIgnoredWhenLocked() {
        var s = session()
        XCTAssertEqual(s.handle(.lockOpen), .refresh)
        XCTAssertTrue(s.isLocked)
        XCTAssertEqual(s.handle(.lockOpen), .none)
        XCTAssertEqual(s.handle(.triggerReleased), .none)
        XCTAssertEqual(s.handle(.commit), .activate(items[1]))
    }

    func testStartingLocked() {
        var s = session(locked: true)
        XCTAssertTrue(s.isLocked)
        XCTAssertEqual(s.handle(.triggerReleased), .none)
    }

    func testTriggerReleasedOnEmptyDismisses() {
        var s = session([])
        XCTAssertEqual(s.handle(.triggerReleased), .dismiss)
    }

    // MARK: - Actions

    func testFocusActionActivates() {
        var s = session()
        XCTAssertEqual(s.handle(.action(.focus)), .activate(items[1]))
    }

    func testWindowActionsPerformOnWindows() {
        // Bundle IDs because pinning needs one (see testTogglePinNeedsABundleID).
        let withBundles = items.map { item -> SwitcherItem in
            var item = item
            item.bundleID = "com.example.\(item.appName)"
            return item
        }
        var s = session(withBundles)
        for action in WindowAction.allCases where action != .focus {
            XCTAssertEqual(s.handle(.action(action)), .perform(action, withBundles[1]), "\(action)")
        }
    }

    func testWindowOnlyActionsAreIgnoredForWindowlessApps() {
        let app = windowlessApp(pid: 9, app: "Calculator")
        var s = session([app])
        XCTAssertEqual(s.handle(.action(.close)), .none)
        XCTAssertEqual(s.handle(.action(.minimize)), .none)
        XCTAssertEqual(s.handle(.action(.toggleFullscreen)), .none)
        XCTAssertEqual(s.handle(.action(.quitApp)), .perform(.quitApp, app))
        XCTAssertEqual(s.handle(.action(.hideApp)), .perform(.hideApp, app))
        XCTAssertEqual(s.handle(.action(.focus)), .activate(app))
    }

    func testActionWithoutSelectionIsNoOp() {
        var s = session([])
        XCTAssertEqual(s.handle(.action(.quitApp)), .none)
        XCTAssertEqual(s.handle(.action(.focus)), .none)
    }

    // MARK: - replaceItems

    func testReplaceItemsKeepsSelectionByID() {
        var s = session()
        s.handle(.select(index: 3)) // Notes
        s.replaceItems([items[3], items[0], items[1]])
        XCTAssertEqual(s.selectedItem?.id, .window(4))
        XCTAssertEqual(s.selectedIndex, 0)
    }

    func testReplaceItemsClampsByIndexWhenSelectedItemIsGone() {
        var s = session()
        s.handle(.select(index: 2))
        s.replaceItems(items.filter { $0.id != .window(3) })
        XCTAssertEqual(s.selectedIndex, 2)
        XCTAssertEqual(s.selectedItem?.id, .window(4))

        s.handle(.last)
        s.replaceItems(Array(items.prefix(4)).filter { $0.id != .window(3) && $0.id != .window(5) })
        XCTAssertEqual(s.selectedIndex, 2, "clamped to the new last index")
    }

    func testReplaceItemsWithEmptyClearsSelection() {
        var s = session()
        s.replaceItems([])
        XCTAssertNil(s.selectedIndex)
        XCTAssertEqual(s.handle(.commit), .dismiss)
    }

    func testReplaceItemsAfterEmptyUsesOpenSelection() {
        var s = session([])
        s.replaceItems(items)
        XCTAssertEqual(s.selectedIndex, 1)
    }

    func testReplaceItemsReappliesQuery() {
        var s = session()
        s.handle(.type("mail"))
        s.replaceItems(items + [window(6, app: "Mail", title: "Drafts")])
        XCTAssertEqual(Set(s.visible.map(\.id)), [.window(3), .window(6)])
        XCTAssertEqual(s.selectedItem?.id, .window(3))
    }

    func testReplaceItemsUpdatesItemContents() {
        var s = session()
        var renamed = items
        renamed[1].title = "vim"
        s.replaceItems(renamed)
        XCTAssertEqual(s.selectedItem?.title, "vim")
        XCTAssertEqual(s.items, renamed)
    }

    // MARK: - New actions

    func testWindowlessAppsIgnoreWindowActionsButCanBePinned() {
        let app = windowlessApp(pid: 9, app: "Calculator", bundle: "com.apple.calculator")
        var s = session([app])
        XCTAssertEqual(s.handle(.action(.moveToNextDisplay)), .none, "no window to move")
        XCTAssertEqual(s.handle(.action(.closeAppWindows)), .none, "no windows to close")
        XCTAssertEqual(s.handle(.action(.togglePin)), .perform(.togglePin, app))
        XCTAssertEqual(s.selectedItem, app, "nothing changes")
    }

    func testTogglePinNeedsABundleID() {
        var s = session() // the fixture's windows have no bundle IDs
        XCTAssertEqual(s.handle(.action(.togglePin)), .none)
        var blank = window(7, bundle: "  ")
        s = session([blank])
        XCTAssertEqual(s.handle(.action(.togglePin)), .none)
        blank.bundleID = "com.example.App"
        s = session([blank])
        XCTAssertEqual(s.handle(.action(.togglePin)), .perform(.togglePin, blank))
        var s2 = session([windowlessApp(pid: 3)])
        XCTAssertEqual(s2.handle(.action(.togglePin)), .none)
    }

    func testMoveAndCloseAppWindowsPerformOnWindows() {
        var s = session()
        XCTAssertEqual(s.handle(.action(.moveToNextDisplay)), .perform(.moveToNextDisplay, items[1]))
        XCTAssertEqual(s.handle(.action(.closeAppWindows)), .perform(.closeAppWindows, items[1]))
        XCTAssertEqual(s.selectedIndex, 1, "actions keep the selection")
    }

    func testNewActionsWhileSearchingUseTheSelectedResult() {
        var s = session()
        s.handle(.type("mail"))
        XCTAssertEqual(s.handle(.action(.moveToNextDisplay)), .perform(.moveToNextDisplay, items[2]))
    }

    func testNewActionsWithoutSelectionAreNoOps() {
        var s = session([])
        for action in [WindowAction.moveToNextDisplay, .closeAppWindows, .togglePin] {
            XCTAssertEqual(s.handle(.action(action)), .none)
        }
    }

    func testWindowActionRawValues() {
        // Raw values are stable identifiers (Codable).
        XCTAssertEqual(WindowAction.moveToNextDisplay.rawValue, "moveToNextDisplay")
        XCTAssertEqual(WindowAction.closeAppWindows.rawValue, "closeAppWindows")
        XCTAssertEqual(WindowAction.togglePin.rawValue, "togglePin")
        XCTAssertEqual(WindowAction.allCases.count, 9)
    }

    // MARK: - Quick select

    func testQuickSelectSelectsAndActivates() {
        var s = session()
        XCTAssertEqual(s.handle(.quickSelect(index: 3)), .activate(items[3]))
        XCTAssertEqual(s.selectedIndex, 3)
    }

    func testQuickSelectOfTheSelectedItemActivates() {
        var s = session()
        XCTAssertEqual(s.handle(.quickSelect(index: 1)), .activate(items[1]))
        XCTAssertEqual(s.handle(.quickSelect(index: 0)), .activate(items[0]))
    }

    func testQuickSelectOutOfRangeChangesNothing() {
        var s = session()
        let before = s
        for index in [5, 6, 100, -1, Int.max, Int.min] {
            XCTAssertEqual(s.handle(.quickSelect(index: index)), .none, "\(index)")
            XCTAssertEqual(s, before)
        }
        var empty = session([])
        XCTAssertEqual(empty.handle(.quickSelect(index: 0)), .none)
        XCTAssertNil(empty.selectedIndex)
    }

    func testQuickSelectIndexesVisibleResultsWhileSearching() {
        var s = session()
        s.handle(.type("s")) // Safari, Notes ("Shopping list"), Terminal (zsh), ...
        let second = s.visible[1].item
        XCTAssertEqual(s.handle(.quickSelect(index: 1)), .activate(second))
        XCTAssertEqual(s.selectedItem, second)
        XCTAssertEqual(s.handle(.quickSelect(index: s.visible.count)), .none)
    }

    func testQuickSelectActivatesEvenWhenLocked() {
        var s = session(locked: true)
        XCTAssertEqual(s.handle(.quickSelect(index: 4)), .activate(items[4]))
    }

    func testQuickSelectWindowlessAppActivates() {
        let app = windowlessApp(pid: 9)
        var s = session([items[0], app])
        XCTAssertEqual(s.handle(.quickSelect(index: 1)), .activate(app))
    }

    // MARK: - Peek

    func testPeekEmitsTheSelectedWindow() {
        var s = session()
        let before = s
        XCTAssertEqual(s.handle(.peek), .peek(items[1]))
        XCTAssertEqual(s, before, "peeking changes no state")
        XCTAssertEqual(s.handle(.peek), .peek(items[1]), "a toggle: the app hides it on the second press")
        s.handle(.next)
        XCTAssertEqual(s.handle(.peek), .peek(items[2]))
    }

    func testPeekWhileSearching() {
        var s = session()
        s.handle(.type("notes"))
        XCTAssertEqual(s.handle(.peek), .peek(items[3]))
    }

    func testPeekNeedsAWindow() {
        var empty = session([])
        XCTAssertEqual(empty.handle(.peek), .none)
        var app = session([windowlessApp(pid: 9)])
        XCTAssertEqual(app.handle(.peek), .none)
        var noMatch = session()
        noMatch.handle(.type("zzzzqqq"))
        XCTAssertNil(noMatch.selectedItem)
        XCTAssertEqual(noMatch.handle(.peek), .none)
    }
}
