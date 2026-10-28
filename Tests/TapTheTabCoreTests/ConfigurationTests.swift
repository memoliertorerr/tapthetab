import XCTest
@testable import TapTheTabCore

final class ConfigurationTests: XCTestCase {
    private func decode(_ json: String) throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    }

    // MARK: - Defaults

    func testDefaults() {
        let c = Configuration()
        XCTAssertEqual(c.version, Configuration.currentVersion)
        XCTAssertEqual(c.triggers, [
            Trigger(shortcut: .optionTab, scope: .allWindows),
            Trigger(shortcut: .optionGrave, scope: .activeApp),
        ])
        XCTAssertEqual(c.filters, FilterOptions())
        XCTAssertEqual(c.appearance.style, .grid)
        XCTAssertEqual(c.appearance.size, .medium)
        XCTAssertFalse(c.appearance.showPreviews)
        XCTAssertTrue(c.appearance.showAppName)
        XCTAssertEqual(c.appearance.theme, .system)
        XCTAssertEqual(c.appearance.placement, .mouse)
        XCTAssertEqual(c.appearance.showDelayMilliseconds, 90)
        XCTAssertTrue(c.behavior.releaseToSwitch)
        XCTAssertTrue(c.behavior.searchEnabled)
        XCTAssertTrue(c.behavior.startOnPrevious)
        XCTAssertTrue(c.behavior.mouseHoverSelects)
        XCTAssertTrue(c.behavior.wrapAround)
    }

    func testDefaultsAreAlreadyValid() {
        let (valid, notes) = Configuration().validated()
        XCTAssertEqual(valid, Configuration())
        XCTAssertEqual(notes, [])
    }

    func testCardSizesGrow() {
        let sizes = ItemSize.allCases.map(\.cardSize)
        XCTAssertEqual(sizes.count, 3)
        XCTAssertLessThan(sizes[0].width, sizes[1].width)
        XCTAssertLessThan(sizes[1].width, sizes[2].width)
        XCTAssertLessThan(sizes[0].height, sizes[1].height)
        XCTAssertLessThan(sizes[1].height, sizes[2].height)
    }

    // MARK: - Decoding

    func testDecodingEmptyObjectGivesDefaults() throws {
        XCTAssertEqual(try decode("{}"), Configuration())
    }

    func testPartialJSONKeepsOtherDefaults() throws {
        let c = try decode(#"{"appearance": {"theme": "dark"}, "behavior": {"wrapAround": false}}"#)
        var expected = Configuration()
        expected.appearance.theme = .dark
        expected.behavior.wrapAround = false
        XCTAssertEqual(c, expected)
    }

    func testShowOtherSpacesIsOffByDefaultAndReadFromFilters() throws {
        XCTAssertFalse(Configuration().filters.showOtherSpaces)
        // Config files written before the key existed keep it off.
        XCTAssertFalse(try decode(#"{"filters": {"currentSpaceOnly": true}}"#).filters.showOtherSpaces)
        XCTAssertTrue(try decode(#"{"filters": {"showOtherSpaces": true}}"#).filters.showOtherSpaces)
        // A bad value turns only this key off; the rest of the section still applies.
        let bad = try decode(#"{"filters": {"showOtherSpaces": "on", "showMinimized": false}}"#)
        XCTAssertFalse(bad.filters.showOtherSpaces)
        XCTAssertFalse(bad.filters.showMinimized)
    }

    func testDecodesTriggers() throws {
        let c = try decode(#"{"triggers": [{"shortcut": "cmd+tab", "scope": "apps"}]}"#)
        XCTAssertEqual(c.triggers, [Trigger(shortcut: .commandTab, scope: .apps)])
    }

    func testUnknownKeysAreIgnored() throws {
        let json = #"{"futureFeature": 1, "appearance": {"sparkles": true, "size": "large"}, "filters": {"x": [1]}}"#
        let c = try decode(json)
        var expected = Configuration()
        expected.appearance.size = .large
        XCTAssertEqual(c, expected)
    }

    func testWrongTypeFallsBackToDefaultForThatKeyOnly() throws {
        let c = try decode(#"{"behavior": {"wrapAround": "yes", "searchEnabled": false}}"#)
        XCTAssertTrue(c.behavior.wrapAround, "bad value falls back to its default")
        XCTAssertFalse(c.behavior.searchEnabled, "valid sibling keys are kept")
    }

    func testUnknownEnumValueFallsBackToDefaultForThatKeyOnly() throws {
        let c = try decode(#"{"appearance": {"theme": "purple", "size": "large"}}"#)
        XCTAssertEqual(c.appearance.theme, .system)
        XCTAssertEqual(c.appearance.size, .large)
    }

    func testInvalidTriggersAreDroppedValidOnesKept() throws {
        let c = try decode(#"{"triggers": [{"shortcut": "hyper+tab", "scope": "apps"}, {"shortcut": "ctrl+tab", "scope": "allWindows"}, {"shortcut": "cmd+tab", "scope": "everything"}]}"#)
        XCTAssertEqual(c.triggers, [Trigger(shortcut: .controlTab, scope: .allWindows)])
    }

    func testAllTriggersInvalidFallsBackToDefaultsAfterValidation() throws {
        let c = try decode(#"{"triggers": [{"shortcut": "nonsense"}]}"#)
        XCTAssertEqual(c.triggers, [])
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, Configuration.defaultTriggers)
        XCTAssertFalse(notes.isEmpty)
    }

    func testWrongTopLevelSectionTypeFallsBack() throws {
        let c = try decode(#"{"filters": "none", "behavior": {"wrapAround": false}}"#)
        XCTAssertEqual(c.filters, FilterOptions())
        XCTAssertFalse(c.behavior.wrapAround)
    }

    func testNonObjectRootThrows() {
        XCTAssertThrowsError(try decode(#"[1, 2, 3]"#))
    }

    func testEncodeDecodeRoundTrip() throws {
        var c = Configuration()
        c.triggers = [Trigger(shortcut: Shortcut(keyCode: KeyCode.space, modifiers: [.control, .option]), scope: .apps)]
        c.filters = FilterOptions(showMinimized: false, showHiddenApps: false, showWindowlessApps: true,
                                  currentSpaceOnly: true, currentDisplayOnly: true, showOtherSpaces: true,
                                  excludedBundleIDs: ["com.a", "com.b"])
        c.appearance.style = .list
        c.appearance.size = .small
        c.appearance.showPreviews = true
        c.appearance.showAppName = false
        c.appearance.theme = .light
        c.appearance.placement = .main
        c.appearance.showDelayMilliseconds = 0
        c.behavior.releaseToSwitch = false
        c.behavior.searchEnabled = false
        c.behavior.startOnPrevious = false
        c.behavior.mouseHoverSelects = false
        c.behavior.wrapAround = false

        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), c)
    }

    func testTriggersEncodeShortcutsAsStrings() throws {
        let data = try JSONEncoder().encode(Configuration())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let triggers = try XCTUnwrap(object["triggers"] as? [[String: Any]])
        XCTAssertEqual(triggers.first?["shortcut"] as? String, "option+tab")
        XCTAssertEqual(triggers.first?["scope"] as? String, "allWindows")
    }

    // MARK: - Validation

    func testDropsModifierlessTriggers() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: Shortcut(keyCode: KeyCode.tab, modifiers: []), scope: .allWindows),
            Trigger(shortcut: Shortcut(keyCode: KeyCode.tab, modifiers: .shift), scope: .allWindows),
            Trigger(shortcut: .commandTab, scope: .apps),
        ]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, [Trigger(shortcut: .commandTab, scope: .apps)])
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.allSatisfy { $0.contains("needs") })
    }

    // Intended change: fn alone used to count, but the event tap ignores fn, so an fn-only
    // trigger captured every plain ⇥ and its session could never end on release.
    func testFnAloneIsNotEnoughForATrigger() {
        var c = Configuration()
        c.triggers = [Trigger(shortcut: Shortcut(keyCode: KeyCode.tab, modifiers: .function), scope: .allWindows)]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, Configuration.defaultTriggers)
        XCTAssertFalse(notes.isEmpty)
    }

    func testFnPlusRealModifierIsKept() {
        var c = Configuration()
        c.triggers = [Trigger(shortcut: Shortcut(keyCode: KeyCode.tab, modifiers: [.function, .option]), scope: .allWindows)]
        XCTAssertEqual(c.validated().0.triggers, c.triggers)
    }

    func testShiftAndFnWithoutRealModifierIsDropped() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: Shortcut(keyCode: KeyCode.tab, modifiers: [.function, .shift]), scope: .allWindows),
            Trigger(shortcut: .optionGrave, scope: .activeApp),
        ]
        XCTAssertEqual(c.validated().0.triggers, [Trigger(shortcut: .optionGrave, scope: .activeApp)])
    }

    func testDropsDuplicateShortcutsKeepingFirst() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows),
            Trigger(shortcut: .optionTab, scope: .apps),
        ]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, [Trigger(shortcut: .optionTab, scope: .allWindows)])
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("twice"))
    }

    func testFallsBackToDefaultTriggersWhenNoneLeft() {
        var c = Configuration()
        c.triggers = [Trigger(shortcut: Shortcut(keyCode: KeyCode.tab, modifiers: []), scope: .allWindows)]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, Configuration.defaultTriggers)
        XCTAssertEqual(notes.count, 2)
    }

    func testEmptyTriggerListFallsBackToDefaults() throws {
        let (valid, notes) = try decode(#"{"triggers": []}"#).validated()
        XCTAssertEqual(valid.triggers, Configuration.defaultTriggers)
        XCTAssertEqual(notes.count, 1)
    }

    func testClampsShowDelay() {
        var c = Configuration()
        c.appearance.showDelayMilliseconds = -50
        var (valid, notes) = c.validated()
        XCTAssertEqual(valid.appearance.showDelayMilliseconds, 0)
        XCTAssertEqual(notes.count, 1)

        c.appearance.showDelayMilliseconds = 5000
        (valid, notes) = c.validated()
        XCTAssertEqual(valid.appearance.showDelayMilliseconds, 1000)
        XCTAssertEqual(notes.count, 1)

        for ok in [0, 1000] {
            c.appearance.showDelayMilliseconds = ok
            (valid, notes) = c.validated()
            XCTAssertEqual(valid.appearance.showDelayMilliseconds, ok)
            XCTAssertEqual(notes, [])
        }
    }

    func testCleansExcludedBundleIDs() {
        var c = Configuration()
        c.filters.excludedBundleIDs = ["  com.a.App ", "", "com.b", "COM.A.APP", "\n", "com.b"]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.filters.excludedBundleIDs, ["com.a.App", "com.b"])
        XCTAssertEqual(notes, [], "cleaning bundle IDs is silent")
    }

    func testNewerVersionAddsNoteAndIsNormalised() {
        var c = Configuration()
        c.version = Configuration.currentVersion + 1
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.version, Configuration.currentVersion)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("newer"))
    }

    func testOlderVersionIsSilentlyUpgraded() {
        var c = Configuration()
        c.version = 0
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.version, Configuration.currentVersion)
        XCTAssertEqual(notes, [])
    }

    func testValidationIsIdempotent() {
        var c = Configuration()
        c.triggers = [Trigger(shortcut: .optionTab, scope: .allWindows), Trigger(shortcut: .optionTab, scope: .apps)]
        c.appearance.showDelayMilliseconds = 9999
        c.filters.excludedBundleIDs = [" a ", "A"]
        let once = c.validated().0
        let (twice, notes) = once.validated()
        XCTAssertEqual(twice, once)
        XCTAssertEqual(notes, [])
    }

    // MARK: - Lookup

    func testTriggerMatching() {
        let c = Configuration()
        XCTAssertEqual(c.trigger(matching: .optionGrave)?.scope, .activeApp)
        XCTAssertEqual(c.trigger(matching: .optionTab)?.scope, .allWindows)
        XCTAssertNil(c.trigger(matching: .commandTab))
    }

    func testMenuBarIconDefaultsToShownAndDecodes() throws {
        XCTAssertTrue(Configuration().appearance.showMenuBarIcon)
        XCTAssertTrue(try decode("{}").appearance.showMenuBarIcon)
        XCTAssertFalse(try decode(#"{"appearance": {"showMenuBarIcon": false}}"#).appearance.showMenuBarIcon)
        XCTAssertTrue(try decode(#"{"appearance": {"showMenuBarIcon": "no"}}"#).appearance.showMenuBarIcon, "bad value falls back")
    }
}
