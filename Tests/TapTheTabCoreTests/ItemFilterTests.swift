import XCTest
@testable import TapTheTabCore

final class ItemFilterTests: XCTestCase {
    private func apply(
        _ items: [SwitcherItem],
        options: FilterOptions = FilterOptions(),
        scope: SwitcherScope = .allWindows,
        context: FilterContext = FilterContext()
    ) -> [ItemID] {
        ItemFilter.apply(items, options: options, scope: scope, context: context).map(\.id)
    }

    // MARK: - Defaults

    func testDefaultOptions() {
        let o = FilterOptions()
        XCTAssertTrue(o.showMinimized)
        XCTAssertTrue(o.showHiddenApps)
        XCTAssertFalse(o.showWindowlessApps)
        XCTAssertFalse(o.currentSpaceOnly)
        XCTAssertFalse(o.currentDisplayOnly)
        XCTAssertEqual(o.excludedBundleIDs, [])
    }

    func testDefaultsKeepEverythingButWindowlessApps() {
        let items = [
            window(1),
            window(2, minimized: true),
            window(3, hidden: true),
            window(4, onActiveSpace: false),
            windowlessApp(pid: 5),
        ]
        XCTAssertEqual(apply(items), [.window(1), .window(2), .window(3), .window(4)])
    }

    func testOrderIsPreserved() {
        let items = [window(9), window(3), window(7), window(1)]
        XCTAssertEqual(apply(items), [.window(9), .window(3), .window(7), .window(1)])
    }

    func testEmptyInput() {
        XCTAssertEqual(apply([], scope: .apps), [])
    }

    // MARK: - Flags

    func testHideMinimized() {
        let items = [window(1), window(2, minimized: true)]
        XCTAssertEqual(apply(items, options: FilterOptions(showMinimized: false)), [.window(1)])
    }

    func testHideHiddenApps() {
        let items = [window(1), window(2, hidden: true), windowlessApp(pid: 3, hidden: true)]
        let options = FilterOptions(showHiddenApps: false, showWindowlessApps: true)
        XCTAssertEqual(apply(items, options: options), [.window(1)])
    }

    func testShowWindowlessApps() {
        let items = [window(1), windowlessApp(pid: 2)]
        XCTAssertEqual(apply(items, options: FilterOptions(showWindowlessApps: true)), [.window(1), .app(pid: 2)])
    }

    func testCurrentSpaceOnly() {
        let items = [window(1), window(2, onActiveSpace: false)]
        XCTAssertEqual(apply(items, options: FilterOptions(currentSpaceOnly: true)), [.window(1)])
    }

    func testCurrentSpaceOnlyKeepsMinimizedHiddenAndWindowless() {
        // These have no meaningful Space, so they must not vanish.
        var app = windowlessApp(pid: 4)
        app.isOnActiveSpace = false
        let items = [
            window(1, minimized: true, onActiveSpace: false),
            window(2, hidden: true, onActiveSpace: false),
            window(3, onActiveSpace: false),
            app,
        ]
        let options = FilterOptions(showWindowlessApps: true, currentSpaceOnly: true)
        XCTAssertEqual(apply(items, options: options), [.window(1), .window(2), .app(pid: 4)])
    }

    func testCurrentDisplayOnly() {
        let items = [window(1, display: 1), window(2, display: 2), window(3, display: nil)]
        let options = FilterOptions(currentDisplayOnly: true)
        XCTAssertEqual(apply(items, options: options, context: FilterContext(activeDisplayID: 1)), [.window(1), .window(3)])
    }

    func testCurrentDisplayOnlyWithoutKnownDisplayKeepsAll() {
        let items = [window(1, display: 1), window(2, display: 2)]
        XCTAssertEqual(apply(items, options: FilterOptions(currentDisplayOnly: true)), [.window(1), .window(2)])
    }

    // MARK: - Exclusions

    func testExcludedBundleIDsAreCaseInsensitive() {
        let items = [
            window(1, bundle: "com.apple.Safari"),
            window(2, bundle: "com.apple.finder"),
            window(3, bundle: nil),
        ]
        let options = FilterOptions(excludedBundleIDs: ["COM.APPLE.SAFARI"])
        XCTAssertEqual(apply(items, options: options), [.window(2), .window(3)])
    }

    func testExcludedBundleAlsoRemovesWindowlessEntry() {
        let items = [windowlessApp(pid: 1, bundle: "com.example.x"), window(2, bundle: "com.example.y")]
        let options = FilterOptions(showWindowlessApps: true, excludedBundleIDs: ["com.example.x"])
        XCTAssertEqual(apply(items, options: options), [.window(2)])
    }

    func testOwnPIDIsRemoved() {
        let items = [window(1, pid: 10), window(2, pid: 99), windowlessApp(pid: 99)]
        let options = FilterOptions(showWindowlessApps: true)
        XCTAssertEqual(apply(items, options: options, context: FilterContext(ownPID: 99)), [.window(1)])
    }

    // MARK: - Scopes

    func testActiveAppScope() {
        let items = [window(1, pid: 1), window(2, pid: 2), window(3, pid: 1), windowlessApp(pid: 1)]
        let options = FilterOptions(showWindowlessApps: true)
        XCTAssertEqual(
            apply(items, options: options, scope: .activeApp, context: FilterContext(activePID: 1)),
            [.window(1), .window(3)]
        )
    }

    func testActiveAppScopeWithoutActivePIDKeepsEverything() {
        let items = [window(1, pid: 1), window(2, pid: 2)]
        XCTAssertEqual(apply(items, scope: .activeApp), [.window(1), .window(2)])
    }

    func testActiveAppScopeStillAppliesFilters() {
        let items = [window(1, pid: 1, minimized: true), window(2, pid: 1)]
        XCTAssertEqual(
            apply(items, options: FilterOptions(showMinimized: false), scope: .activeApp, context: FilterContext(activePID: 1)),
            [.window(2)]
        )
    }

    func testAppsScopeKeepsFirstPerPID() {
        let items = [
            window(1, pid: 1),
            window(2, pid: 2),
            window(3, pid: 1),
            windowlessApp(pid: 3),
            window(4, pid: 2),
        ]
        let options = FilterOptions(showWindowlessApps: true)
        XCTAssertEqual(apply(items, options: options, scope: .apps), [.window(1), .window(2), .app(pid: 3)])
    }

    func testAppsScopeRunsAfterFilters() {
        // The first window of pid 1 is minimized and filtered out, so the next one represents the app.
        let items = [window(1, pid: 1, minimized: true), window(2, pid: 1)]
        XCTAssertEqual(apply(items, options: FilterOptions(showMinimized: false), scope: .apps), [.window(2)])
    }

    func testScopeCodableRawValues() {
        XCTAssertEqual(SwitcherScope.allCases.map(\.rawValue), ["allWindows", "activeApp", "apps"])
    }

    // MARK: - Decoding

    func testDecodingEmptyObjectGivesDefaults() throws {
        let decoded = try JSONDecoder().decode(FilterOptions.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, FilterOptions())
    }

    func testDecodingPartialObjectKeepsOtherDefaults() throws {
        let json = #"{"showMinimized": false, "excludedBundleIDs": ["a.b"]}"#
        let decoded = try JSONDecoder().decode(FilterOptions.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, FilterOptions(showMinimized: false, excludedBundleIDs: ["a.b"]))
    }
}
