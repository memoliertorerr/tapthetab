import XCTest
@testable import TapTheTabCore

final class SpaceCoverageTests: XCTestCase {
    // MARK: - SpaceCoverage

    func testCoverageFromStoredKeys() {
        XCTAssertEqual(SpaceCoverage(FilterOptions()), .automatic)
        XCTAssertEqual(SpaceCoverage(FilterOptions(currentSpaceOnly: true)), .currentDesktop)
        XCTAssertEqual(SpaceCoverage(FilterOptions(showOtherSpaces: true)), .allDesktops)
        // Older configs could have both on; the strict setting always won at run time.
        XCTAssertEqual(SpaceCoverage(FilterOptions(currentSpaceOnly: true, showOtherSpaces: true)), .currentDesktop)
    }

    func testApplyingSetsBothKeysAndNothingElse() {
        let base = FilterOptions(
            showMinimized: false, showHiddenApps: false, showWindowlessApps: true,
            currentSpaceOnly: true, currentDisplayOnly: true, showOtherSpaces: true,
            excludedBundleIDs: ["a"], pinnedBundleIDs: ["b"], currentDisplayFirst: true
        )
        for coverage in SpaceCoverage.allCases {
            let applied = coverage.applied(to: base)
            XCTAssertEqual(SpaceCoverage(applied), coverage)
            XCTAssertEqual(applied.currentSpaceOnly, coverage == .currentDesktop)
            XCTAssertEqual(applied.showOtherSpaces, coverage == .allDesktops)
            var rest = applied
            rest.currentSpaceOnly = base.currentSpaceOnly
            rest.showOtherSpaces = base.showOtherSpaces
            XCTAssertEqual(rest, base, "\(coverage)")
        }
    }

    func testAppliedCoverageKeepsTheStoredKeys() throws {
        let options = SpaceCoverage.allDesktops.applied(to: FilterOptions())
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any]
        XCTAssertEqual(object?["showOtherSpaces"] as? Bool, true)
        XCTAssertEqual(object?["currentSpaceOnly"] as? Bool, false)
        let decoded = try JSONDecoder().decode(FilterOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(decoded, options)
    }

    func testOtherSpacesPassMatchesTheEarlierRule() {
        // The catalog used to be configured with showOtherSpaces && !currentSpaceOnly.
        for strict in [false, true] {
            for others in [false, true] {
                let options = FilterOptions(currentSpaceOnly: strict, showOtherSpaces: others)
                XCTAssertEqual(SpaceCoverage.listsOtherSpaces(options), others && !strict)
            }
        }
    }

    // MARK: - FullscreenEscape

    func testStrictCoveragePreservesWindowlessAppsByDisablingRetention() {
        XCTAssertTrue(SpaceCoverage.retainsSeenWindows(FilterOptions()))
        XCTAssertTrue(SpaceCoverage.retainsSeenWindows(FilterOptions(showOtherSpaces: true)))
        for showWindowless in [false, true] {
            for otherSpaces in [false, true] {
                let options = FilterOptions(showWindowlessApps: showWindowless, currentSpaceOnly: true, showOtherSpaces: otherSpaces)
                XCTAssertFalse(SpaceCoverage.retainsSeenWindows(options),
                               "strict coverage must not replace an app entry with an off-Space window")
            }
        }
    }

    func testFullscreenShownNeedsAnOnScreenFullscreenWindow() {
        XCTAssertFalse(FullscreenEscape.isFullscreenShown([window(1), windowlessApp(pid: 2)]))
        XCTAssertTrue(FullscreenEscape.isFullscreenShown([window(1, fullscreen: true)]))
        // A full-screen window on a Space that isn't shown, or minimized, doesn't count.
        XCTAssertFalse(FullscreenEscape.isFullscreenShown([window(1, fullscreen: true, onActiveSpace: false)]))
        XCTAssertFalse(FullscreenEscape.isFullscreenShown([window(1, minimized: true, fullscreen: true)]))
        XCTAssertFalse(FullscreenEscape.isFullscreenShown([window(1, hidden: true, fullscreen: true)]))
    }

    func testEscapeIsForTheActiveAppOrTheSwitchersDisplay() {
        let video = window(1, pid: 10, fullscreen: true, display: 2)
        XCTAssertTrue(FullscreenEscape.isActive([video], context: FilterContext()))
        XCTAssertTrue(FullscreenEscape.isActive([video], context: FilterContext(activePID: 10, activeDisplayID: 1)))
        XCTAssertTrue(FullscreenEscape.isActive([video], context: FilterContext(activePID: 20, activeDisplayID: 2)))
        // A video playing full screen on another display while working elsewhere.
        XCTAssertFalse(FullscreenEscape.isActive([video], context: FilterContext(activePID: 20, activeDisplayID: 1)))
    }

    // MARK: - SeenWindowRetention

    /// Desktop: a browser window that is about to go full screen and two documents.
    private let desktop = [
        window(1, pid: 1),
        window(2, pid: 2),
        window(3, pid: 3),
    ]

    private func decide(
        previous: [SwitcherItem],
        heldBack: [SwitcherItem] = [],
        current: [SwitcherItem],
        answered: Set<Int32> = [1, 2, 3, 4],
        ignored: Set<UInt32> = [],
        onScreen: Set<UInt32>,
        alive: [UInt32: Int32] = [1: 1, 2: 2, 3: 3, 4: 4, 5: 2]
    ) -> SeenWindowRetention.Outcome {
        SeenWindowRetention.decide(
            previous: previous, heldBack: heldBack, current: current, answeredPIDs: answered,
            ignoredIDs: ignored, onScreenIDs: onScreen, windowServerOwners: alive
        )
    }

    func testEnteringFullscreenKeepsTheDesktopsWindows() {
        // The video's Space only has the video; the Accessibility API lists nothing else.
        let current = [window(1, pid: 1, fullscreen: true), windowlessApp(pid: 2), windowlessApp(pid: 3)]
        let outcome = decide(previous: desktop, current: current, onScreen: [1])
        XCTAssertEqual(outcome.kept.map(\.id), [.window(2), .window(3)])
        XCTAssertTrue(outcome.kept.allSatisfy { !$0.isOnActiveSpace })
        XCTAssertEqual(outcome.vanished, [])
    }

    func testOnlyFullscreenKeepsWindows() {
        // Switching to another ordinary desktop: unchanged behaviour, nothing is kept.
        let current = [window(7, pid: 1), windowlessApp(pid: 2), windowlessApp(pid: 3)]
        let outcome = decide(previous: desktop, current: current, onScreen: [7])
        XCTAssertEqual(outcome.kept, [])
        XCTAssertEqual(outcome.vanished.map(\.id), [.window(1), .window(2), .window(3)])
    }

    func testKeptWindowsStayWhileFullscreenIsShown() {
        let previous = [window(1, pid: 1, fullscreen: true), window(2, pid: 2, onActiveSpace: false)]
        let current = [window(1, pid: 1, fullscreen: true), windowlessApp(pid: 2)]
        XCTAssertEqual(decide(previous: previous, current: current, onScreen: [1]).kept.map(\.id), [.window(2)])
    }

    func testWindowClosedWhileFullscreenStaysShownIsDropped() {
        // Full screen on one display, a window closed (only ordered out) on the other.
        let previous = [window(1, pid: 1, fullscreen: true), window(2, pid: 2)]
        let current = [window(1, pid: 1, fullscreen: true), windowlessApp(pid: 2)]
        let outcome = decide(previous: previous, current: current, onScreen: [1])
        XCTAssertEqual(outcome.kept, [])
        XCTAssertEqual(outcome.vanished.map(\.id), [.window(2)])
    }

    func testSwitchingBetweenFullscreenSpacesKeepsTheOtherVideo() {
        let previous = [window(1, pid: 1, fullscreen: true), window(2, pid: 2, onActiveSpace: false), window(4, pid: 4, fullscreen: true, onActiveSpace: false)]
        let current = [window(4, pid: 4, fullscreen: true), windowlessApp(pid: 1), windowlessApp(pid: 2)]
        let outcome = decide(previous: previous, current: current, onScreen: [4])
        XCTAssertEqual(outcome.kept.map(\.id), [.window(1), .window(2)])
        XCTAssertTrue(outcome.kept[0].isFullscreen, "keeps what was known about the window")
    }

    func testWindowsTheWindowServerNoLongerHasAreDropped() {
        let current = [window(1, pid: 1, fullscreen: true)]
        let outcome = decide(previous: desktop, current: current, onScreen: [1], alive: [1: 1, 3: 3])
        XCTAssertEqual(outcome.kept.map(\.id), [.window(3)])
        XCTAssertEqual(outcome.vanished, [])
    }

    func testReusedWindowNumberOfAnotherAppIsDropped() {
        let current = [window(1, pid: 1, fullscreen: true)]
        let outcome = decide(previous: desktop, current: current, onScreen: [1], alive: [1: 1, 2: 9, 3: 3])
        XCTAssertEqual(outcome.kept.map(\.id), [.window(3)])
    }

    func testOnlyAppsThatAnsweredCanLoseWindows() {
        // App 3 was busy, hidden or not asked: its windows are the app pass's business.
        let current = [window(1, pid: 1, fullscreen: true)]
        let outcome = decide(previous: desktop, current: current, answered: [1, 2], onScreen: [1])
        XCTAssertEqual(outcome.kept.map(\.id), [.window(2)])
        XCTAssertEqual(outcome.vanished, [])
    }

    func testNothingIsListedTwice() {
        // Still listed by the Accessibility API (or reused), so not a candidate.
        let current = [window(1, pid: 1, fullscreen: true), window(2, pid: 2, onActiveSpace: false)]
        let outcome = decide(previous: desktop + [window(2, pid: 2)], heldBack: [window(3, pid: 3)], current: current, onScreen: [1])
        XCTAssertEqual(outcome.kept.map(\.id), [.window(3)])
    }

    func testIgnoredOnScreenAndMinimizedWindowsAreNotKept() {
        let previous = desktop + [window(5, pid: 2, minimized: true)]
        let current = [window(1, pid: 1, fullscreen: true)]
        // 2 is now a panel the app doesn't count as a window; 3 is on screen but unlisted.
        let outcome = decide(previous: previous, current: current, ignored: [2], onScreen: [1, 3])
        XCTAssertEqual(outcome.kept, [])
        XCTAssertEqual(outcome.vanished, [])
    }

    func testFullscreenReportedLateStillKeepsTheDesktop() {
        // First refresh after the Space change: the video isn't reported as full screen yet.
        let first = decide(previous: desktop, current: [window(1, pid: 1), windowlessApp(pid: 2), windowlessApp(pid: 3)], onScreen: [1])
        XCTAssertEqual(first.kept, [])
        XCTAssertEqual(first.vanished.map(\.id), [.window(2), .window(3)])
        // Next refresh: it is. The held-back windows get their one more chance.
        let previous = [window(1, pid: 1), windowlessApp(pid: 2), windowlessApp(pid: 3)]
        let second = decide(previous: previous, heldBack: first.vanished, current: [window(1, pid: 1, fullscreen: true), windowlessApp(pid: 2), windowlessApp(pid: 3)], onScreen: [1])
        XCTAssertEqual(second.kept.map(\.id), [.window(2), .window(3)])
    }

    func testHeldBackWindowsAreNotCarriedFurther() {
        let previous = [window(1, pid: 1, fullscreen: true)]
        let outcome = decide(previous: previous, heldBack: [window(2, pid: 2)], current: [window(1, pid: 1, fullscreen: true)], onScreen: [1])
        XCTAssertEqual(outcome.kept, [])
        XCTAssertEqual(outcome.vanished, [], "a closed window must not wait for the next Space change")
    }

    func testEnteredFullscreen() {
        XCTAssertTrue(SeenWindowRetention.enteredFullscreen(now: [window(1, fullscreen: true)], previous: [window(1)]))
        XCTAssertTrue(SeenWindowRetention.enteredFullscreen(now: [window(1, fullscreen: true)], previous: [window(1, fullscreen: true, onActiveSpace: false)]))
        XCTAssertFalse(SeenWindowRetention.enteredFullscreen(now: [window(1, fullscreen: true)], previous: [window(1, fullscreen: true)]))
        XCTAssertFalse(SeenWindowRetention.enteredFullscreen(now: [window(1)], previous: []))
    }
}
