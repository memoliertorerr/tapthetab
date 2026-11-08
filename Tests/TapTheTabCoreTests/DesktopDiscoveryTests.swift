import XCTest
@testable import TapTheTabCore

/// One catalog for shortcuts with different desktop coverage: what it looks for, and how
/// each switcher sees it.
final class DesktopDiscoveryTests: XCTestCase {
    // MARK: - What the catalog looks for

    func testSingleCoverageDiscoversExactlyAsBefore() {
        // Before, the catalog was configured from the filters alone: the other-Spaces pass
        // with `listsOtherSpaces`, the seen-window pass with `retainsSeenWindows` only
        // when that pass did not run.
        for strict in [false, true] {
            for others in [false, true] {
                let options = FilterOptions(currentSpaceOnly: strict, showOtherSpaces: others)
                let discovery = DesktopDiscovery(coverages: [SpaceCoverage(options)])
                XCTAssertEqual(discovery.listsOtherSpaces, SpaceCoverage.listsOtherSpaces(options), "\(options)")
                for listed in discovery.listsOtherSpaces ? [false, true] : [false] {
                    let before = !listed && SpaceCoverage.retainsSeenWindows(options)
                    XCTAssertEqual(discovery.keepsSeenWindows(otherSpacesListed: listed), before, "\(options) listed: \(listed)")
                }
            }
        }
    }

    func testDefaultsUsePublicInterfacesOnly() {
        let discovery = DesktopDiscovery(Configuration())
        XCTAssertFalse(discovery.listsOtherSpaces, "every desktop is listed only by choice")
        XCTAssertTrue(discovery.retainsSeenWindows)
    }

    func testOneAllDesktopsShortcutKeepsTheCatalogComplete() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows, desktopCoverage: .allDesktops),
            Trigger(shortcut: .optionGrave, scope: .activeApp),
        ]
        let discovery = DesktopDiscovery(c)
        // Also while no switcher is open, so the first quick tap finds every desktop.
        XCTAssertTrue(discovery.listsOtherSpaces)
        // The inheriting shortcut still gets the public full-screen escape.
        XCTAssertTrue(discovery.keepsSeenWindows(otherSpacesListed: true))
        XCTAssertTrue(SpaceCoverage.allCases.allSatisfy(discovery.covers))
    }

    func testStrictAndAllDesktopsDoNotKeepSeenWindows() {
        let discovery = DesktopDiscovery(coverages: [.currentDesktop, .allDesktops])
        XCTAssertTrue(discovery.listsOtherSpaces)
        XCTAssertFalse(discovery.keepsSeenWindows(otherSpacesListed: true))
        XCTAssertTrue(discovery.keepsSeenWindows(otherSpacesListed: false), "the fallback without the private listing")
        XCTAssertFalse(discovery.covers(.automatic))
    }

    func testCovers() {
        XCTAssertTrue(DesktopDiscovery().covers(.currentDesktop))
        XCTAssertFalse(DesktopDiscovery().covers(.automatic))
        XCTAssertFalse(DesktopDiscovery().covers(.allDesktops))
        XCTAssertTrue(DesktopDiscovery(retainsSeenWindows: true).covers(.automatic))
        XCTAssertFalse(DesktopDiscovery(retainsSeenWindows: true).covers(.allDesktops))
        XCTAssertTrue(DesktopDiscovery(listsOtherSpaces: true).covers(.allDesktops))
    }

    func testDiscoveryChangesOnlyWithTheCoveragesInUse() {
        var c = Configuration()
        let before = DesktopDiscovery(c)
        c.triggers[1].style = .list
        c.triggers[1].scope = .apps
        XCTAssertEqual(DesktopDiscovery(c), before)
        c.triggers[1].desktopCoverage = .automatic // the same as inherited
        XCTAssertEqual(DesktopDiscovery(c), before)
        c.triggers[1].desktopCoverage = .allDesktops
        XCTAssertNotEqual(DesktopDiscovery(c), before, "a change asks for a full refresh")
    }

    // MARK: - A catalog built for several coverages

    /// The user is in a full-screen video (pid 1). Pid 2's window 2 was seen before and is
    /// kept; pid 3 was never visited, its window 3 only the other-Spaces pass found; pid 4
    /// has a minimized window the Accessibility API lists; pid 5 has no windows at all.
    /// The catalog keeps the app entries of 2 and 3 next to their discovered windows.
    private let video = window(1, pid: 1, fullscreen: true)
    private var mixed: [SwitcherItem] {
        [
            video,
            window(4, pid: 4, minimized: true, onActiveSpace: false),
            window(2, pid: 2, onActiveSpace: false),
            window(3, pid: 3, onActiveSpace: false),
            windowlessApp(pid: 2),
            windowlessApp(pid: 3),
            windowlessApp(pid: 5),
        ]
    }
    private let origins: [ItemID: ItemOrigin] = [.window(2): .retained, .window(3): .otherSpaces]

    func testAllDesktopsSeesEverything() {
        let items = CoverageView.items(mixed, origins: origins, coverage: .allDesktops)
        XCTAssertEqual(items.map(\.id), [.window(1), .window(4), .window(2), .window(3), .app(pid: 5)])
    }

    func testDefaultCoverageNeverSeesWhatOnlyTheOtherSpacesPassFound() {
        let items = CoverageView.items(mixed, origins: origins, coverage: .automatic)
        XCTAssertEqual(items.map(\.id), [.window(1), .window(4), .window(2), .app(pid: 3), .app(pid: 5)])
    }

    func testCurrentDesktopSeesOnlyListedWindowsAndGetsAppEntriesBack() {
        let items = CoverageView.items(mixed, origins: origins, coverage: .currentDesktop)
        XCTAssertEqual(items.map(\.id), [.window(1), .window(4), .app(pid: 2), .app(pid: 3), .app(pid: 5)])
    }

    func testDefaultCoverageMatchesACatalogThatNeverListedOtherSpaces() {
        // What a catalog configured for the default coverage alone built: the kept window
        // replaced its app's entry; pid 3 looked windowless.
        let alone = [video, window(4, pid: 4, minimized: true, onActiveSpace: false), window(2, pid: 2, onActiveSpace: false), windowlessApp(pid: 3), windowlessApp(pid: 5)]
        let options = FilterOptions()
        let context = FilterContext(activePID: 1)
        for scope in SwitcherScope.allCases {
            let shared = ItemFilter.apply(CoverageView.items(mixed, origins: origins, coverage: .automatic), options: options, scope: scope, context: context)
            let separate = ItemFilter.apply(CoverageView.items(alone, origins: [.window(2): .retained], coverage: .automatic), options: options, scope: scope, context: context)
            XCTAssertEqual(shared, separate, "\(scope)")
        }
        // The full-screen escape still lists the apps it can't see into.
        let listed = ItemFilter.apply(CoverageView.items(mixed, origins: origins, coverage: .automatic), options: options, scope: .allWindows, context: context)
        XCTAssertEqual(listed.map(\.id), [.window(1), .window(4), .window(2), .app(pid: 3), .app(pid: 5)])
    }

    func testStrictShortcutMatchesACatalogThatLookedNoFurther() {
        let alone = [video, window(4, pid: 4, minimized: true, onActiveSpace: false), windowlessApp(pid: 2), windowlessApp(pid: 3), windowlessApp(pid: 5)]
        for showWindowless in [false, true] {
            let options = FilterOptions(showWindowlessApps: showWindowless, currentSpaceOnly: true)
            for scope in SwitcherScope.allCases {
                for active in [Int32(1), 2, 3] {
                    let context = FilterContext(activePID: active)
                    let shared = ItemFilter.apply(CoverageView.items(mixed, origins: origins, coverage: .currentDesktop), options: options, scope: scope, context: context)
                    let separate = ItemFilter.apply(alone, options: options, scope: scope, context: context)
                    XCTAssertEqual(shared, separate, "\(scope) active \(active) windowless \(showWindowless)")
                }
            }
        }
        // The current app's shortcut from an app whose window is on another desktop
        // offers the app (activating it reopens a window), never that window.
        let strict = FilterOptions(currentSpaceOnly: true)
        let current = ItemFilter.apply(CoverageView.items(mixed, origins: origins, coverage: .currentDesktop), options: strict, scope: .activeApp, context: FilterContext(activePID: 3))
        XCTAssertEqual(current.map(\.id), [.app(pid: 3)])
    }

    func testQuickTapTargetFollowsTheShortcut() {
        // Recency: the video, then the never-visited window, then the kept one.
        let ordered = [video, window(3, pid: 3, onActiveSpace: false), window(2, pid: 2, onActiveSpace: false), window(6, pid: 6), windowlessApp(pid: 3), windowlessApp(pid: 2)]
        func second(_ coverage: SpaceCoverage) -> ItemID? {
            let options = coverage.applied(to: FilterOptions())
            let list = ItemFilter.apply(CoverageView.items(ordered, origins: origins, coverage: coverage), options: options, scope: .allWindows, context: FilterContext(activePID: 1))
            return list.count > 1 ? list[1].id : nil
        }
        XCTAssertEqual(second(.allDesktops), .window(3))
        XCTAssertEqual(second(.automatic), .window(2))
        XCTAssertEqual(second(.currentDesktop), .window(6))
    }

    func testWindowsNowOnTheCurrentSpaceAreShownToEveryCoverage() {
        // Reused for an app that wasn't asked again; the window server says it's on screen.
        let items = [window(3, pid: 3, onActiveSpace: true), window(2, pid: 2, onActiveSpace: true)]
        for coverage in SpaceCoverage.allCases {
            XCTAssertEqual(CoverageView.items(items, origins: origins, coverage: coverage), items, "\(coverage)")
        }
    }

    func testAnAppLeftWithNothingGetsOneEntryAtTheEnd() {
        // A busy app keeps its last windows without its own entry.
        let items = [window(3, pid: 3, app: "Notes", bundle: "com.example.notes", hidden: true, onActiveSpace: false), window(7, pid: 3, onActiveSpace: false), window(1, pid: 1)]
        let seen = CoverageView.items(items, origins: [.window(3): .otherSpaces, .window(7): .otherSpaces], coverage: .automatic)
        XCTAssertEqual(seen.map(\.id), [.window(1), .app(pid: 3)])
        let entry = seen.last
        XCTAssertEqual(entry?.appName, "Notes")
        XCTAssertEqual(entry?.bundleID, "com.example.notes")
        XCTAssertEqual(entry?.isAppHidden, true)
        XCTAssertTrue(entry?.isWindowless ?? false)
    }

    func testAppEntriesAreNeverDoubled() {
        let items = [windowlessApp(pid: 2), window(2, pid: 2, onActiveSpace: false), windowlessApp(pid: 2)]
        let seen = CoverageView.items(items, origins: [.window(2): .otherSpaces], coverage: .currentDesktop)
        XCTAssertEqual(seen.map(\.id), [.app(pid: 2)])
    }

    func testPlainCatalogsAreUnchanged() {
        // Without discovered entries every coverage sees the catalog as it is.
        var generator = CoverageCaseGenerator(seed: 0x5EED_0057)
        for _ in 0..<200 {
            var items: [SwitcherItem] = []
            var windowless = Set<Int32>()
            for number in 1...UInt32(generator.next() % 12 + 1) {
                let pid = Int32(generator.next() % 6)
                if generator.next() % 4 == 0, !items.contains(where: { $0.pid == pid }), windowless.insert(pid).inserted {
                    items.append(windowlessApp(pid: pid))
                } else if !windowless.contains(pid) {
                    items.append(window(number, pid: pid, minimized: generator.next() % 5 == 0, onActiveSpace: generator.next() % 3 != 0))
                }
            }
            for coverage in SpaceCoverage.allCases {
                XCTAssertEqual(CoverageView.items(items, origins: [:], coverage: coverage), items)
            }
        }
    }

    // MARK: - Seen windows with another shortcut listing every desktop

    func testSeenWindowsNeverIncludeWhatOnlyTheOtherSpacesPassFound() {
        let previous = [window(10, pid: 1), window(2, pid: 2), window(3, pid: 3, onActiveSpace: false), windowlessApp(pid: 3)]
        let seen = CoverageView.seenItems(previous, origins: [.window(3): .otherSpaces])
        XCTAssertEqual(seen.map(\.id), [.window(10), .window(2), .app(pid: 3)])
        XCTAssertEqual(CoverageView.seenItems(previous, origins: [:]), previous)

        // Entering a full-screen video: only the window TapTheTab saw is kept.
        let outcome = SeenWindowRetention.decide(
            previous: seen,
            current: [window(1, pid: 1, fullscreen: true), windowlessApp(pid: 2), windowlessApp(pid: 3)],
            answeredPIDs: [1, 2, 3],
            ignoredIDs: [],
            onScreenIDs: [1],
            windowServerOwners: [1: 1, 2: 2, 3: 3]
        )
        XCTAssertEqual(outcome.kept.map(\.id), [.window(2)])
    }

    func testOriginShows() {
        XCTAssertTrue(SpaceCoverage.allCases.allSatisfy { CoverageView.shows(.listed, coverage: $0) })
        XCTAssertEqual(SpaceCoverage.allCases.filter { CoverageView.shows(.retained, coverage: $0) }, [.automatic, .allDesktops])
        XCTAssertEqual(SpaceCoverage.allCases.filter { CoverageView.shows(.otherSpaces, coverage: $0) }, [.allDesktops])
    }
}

/// Small deterministic generator for repeatable generated cases.
private struct CoverageCaseGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
