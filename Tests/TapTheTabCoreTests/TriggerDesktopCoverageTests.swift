import XCTest
@testable import TapTheTabCore

/// Desktop coverage per shortcut: config compatibility and the filters a shortcut uses.
final class TriggerDesktopCoverageTests: XCTestCase {
    private func decode(_ json: String) throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    // MARK: - Decoding and encoding

    func testOlderTriggersInherit() throws {
        let c = try decode(#"{"triggers": [{"shortcut": "option+tab", "scope": "allWindows"}, {"shortcut": "option+grave", "scope": "activeApp", "style": "list"}]}"#)
        XCTAssertEqual(c.triggers.count, 2)
        XCTAssertTrue(c.triggers.allSatisfy { $0.desktopCoverage == nil })
        XCTAssertEqual(c.triggers[1].style, .list)
        XCTAssertTrue(Configuration.defaultTriggers.allSatisfy { $0.desktopCoverage == nil }, "defaults inherit")
        XCTAssertTrue(Configuration().triggers.allSatisfy { $0.desktopCoverage == nil })
        XCTAssertNil(Trigger(shortcut: .optionTab, scope: .allWindows).desktopCoverage)
    }

    func testEveryCoverageRoundTripsUnderItsStoredName() throws {
        let names: [SpaceCoverage: String] = [.currentDesktop: "currentDesktop", .automatic: "automatic", .allDesktops: "allDesktops"]
        XCTAssertEqual(Set(names.keys), Set(SpaceCoverage.allCases))
        for (coverage, name) in names {
            let trigger = Trigger(shortcut: .optionTab, scope: .apps, style: .list, desktopCoverage: coverage)
            let encoded = try object(trigger)
            XCTAssertEqual(encoded["desktopCoverage"] as? String, name)
            XCTAssertEqual(encoded["style"] as? String, "list")
            XCTAssertEqual(try JSONDecoder().decode(Trigger.self, from: JSONEncoder().encode(trigger)), trigger)

            let c = try decode(#"{"triggers": [{"shortcut": "cmd+tab", "scope": "allWindows", "desktopCoverage": "\#(name)"}]}"#)
            XCTAssertEqual(c.triggers, [Trigger(shortcut: .commandTab, scope: .allWindows, desktopCoverage: coverage)])
        }
    }

    func testInheritingIsNotWritten() throws {
        let encoded = try object(Trigger(shortcut: .optionTab, scope: .allWindows))
        XCTAssertEqual(Set(encoded.keys), ["shortcut", "scope"], "older versions read the same file as before")
    }

    func testBadCoverageKeepsTheTriggerAndInherits() throws {
        for bad in [#""everywhere""#, #""AllDesktops""#, #""all-desktops""#, #""""#, "1", "true", "null", "[]", #"{"a": 1}"#] {
            let c = try decode(#"{"triggers": [{"shortcut": "cmd+tab", "scope": "apps", "style": "grid", "desktopCoverage": \#(bad)}]}"#)
            XCTAssertEqual(c.triggers, [Trigger(shortcut: .commandTab, scope: .apps, style: .grid)], bad)
        }
    }

    func testCoverageAloneDoesNotMakeATrigger() throws {
        let c = try decode(#"{"triggers": [{"shortcut": "cmd+tab", "desktopCoverage": "allDesktops"}, {"scope": "apps", "desktopCoverage": "allDesktops"}, {"shortcut": "ctrl+tab", "scope": "allWindows", "desktopCoverage": "currentDesktop"}]}"#)
        XCTAssertEqual(c.triggers, [Trigger(shortcut: .controlTab, scope: .allWindows, desktopCoverage: .currentDesktop)])
    }

    func testValidationKeepsCoverageAndStillDropsDuplicates() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows, desktopCoverage: .allDesktops),
            Trigger(shortcut: .optionTab, scope: .allWindows, desktopCoverage: .currentDesktop),
            Trigger(shortcut: .optionGrave, scope: .activeApp, desktopCoverage: .currentDesktop),
            Trigger(shortcut: .commandGrave, scope: .apps),
        ]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, [c.triggers[0], c.triggers[2], c.triggers[3]])
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("twice"))
    }

    func testMixedConfigurationRoundTripsAndKeepsTheGlobalKeys() throws {
        var c = Configuration()
        c.filters.currentSpaceOnly = true
        c.filters.showOtherSpaces = true // an older file with both on
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows, desktopCoverage: .allDesktops),
            Trigger(shortcut: .optionGrave, scope: .activeApp),
            Trigger(shortcut: .commandGrave, scope: .apps, style: .list, desktopCoverage: .automatic),
        ]
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), c)
        let filters = try XCTUnwrap((try object(c))["filters"] as? [String: Any])
        XCTAssertEqual(filters["currentSpaceOnly"] as? Bool, true)
        XCTAssertEqual(filters["showOtherSpaces"] as? Bool, true)
        XCTAssertNil(filters["desktopCoverage"], "the global choice keeps its two keys")
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid, c)
        XCTAssertEqual(notes, [])
    }

    // MARK: - Effective filters

    func testInheritingUsesTheFiltersUnchanged() {
        let combos = [
            FilterOptions(),
            FilterOptions(currentSpaceOnly: true),
            FilterOptions(showOtherSpaces: true),
            FilterOptions(currentSpaceOnly: true, showOtherSpaces: true),
        ]
        let trigger = Trigger(shortcut: .optionTab, scope: .allWindows)
        for options in combos {
            XCTAssertEqual(options.effective(for: trigger), options, "\(options)")
        }
    }

    func testOwnCoverageReplacesOnlyTheTwoDesktopKeys() {
        let base = FilterOptions(
            showMinimized: false, showHiddenApps: false, showWindowlessApps: true,
            currentSpaceOnly: true, currentDisplayOnly: true, showOtherSpaces: true,
            excludedBundleIDs: ["a"], pinnedBundleIDs: ["b"], currentDisplayFirst: true
        )
        for coverage in SpaceCoverage.allCases {
            let effective = base.effective(for: Trigger(shortcut: .optionTab, scope: .allWindows, desktopCoverage: coverage))
            XCTAssertEqual(SpaceCoverage(effective), coverage)
            XCTAssertEqual(effective, coverage.applied(to: base))
            var rest = effective
            rest.currentSpaceOnly = base.currentSpaceOnly
            rest.showOtherSpaces = base.showOtherSpaces
            XCTAssertEqual(rest, base, "\(coverage)")
        }
    }

    func testFocusAcrossSpacesFollowsTheShortcut() {
        let all = Trigger(shortcut: .optionTab, scope: .allWindows, desktopCoverage: .allDesktops)
        let strict = Trigger(shortcut: .optionGrave, scope: .activeApp, desktopCoverage: .currentDesktop)
        let inherit = Trigger(shortcut: .commandGrave, scope: .apps)
        XCTAssertTrue(SpaceCoverage.listsOtherSpaces(FilterOptions().effective(for: all)))
        XCTAssertFalse(SpaceCoverage.listsOtherSpaces(FilterOptions().effective(for: inherit)))
        let global = FilterOptions(showOtherSpaces: true)
        XCTAssertFalse(SpaceCoverage.listsOtherSpaces(global.effective(for: strict)))
        XCTAssertTrue(SpaceCoverage.listsOtherSpaces(global.effective(for: inherit)))
    }

    func testCoverageForATriggerAndCoveragesInUse() {
        var c = Configuration()
        XCTAssertEqual(c.desktopCoveragesInUse, [.automatic])
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows, desktopCoverage: .allDesktops),
            Trigger(shortcut: .optionGrave, scope: .activeApp, desktopCoverage: .currentDesktop),
        ]
        XCTAssertEqual(c.desktopCoverage(for: c.triggers[0]), .allDesktops)
        XCTAssertEqual(c.desktopCoverage(for: Trigger(shortcut: .commandTab, scope: .apps)), .automatic)
        // The filters' own choice stays in use: links and the menu can open with it.
        XCTAssertEqual(c.desktopCoveragesInUse, [.allDesktops, .currentDesktop, .automatic])
        c.filters.currentSpaceOnly = true
        XCTAssertEqual(c.desktopCoveragesInUse, [.allDesktops, .currentDesktop])
    }
}
