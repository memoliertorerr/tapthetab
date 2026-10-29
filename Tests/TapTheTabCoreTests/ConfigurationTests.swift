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
        XCTAssertFalse(c.appearance.groupByApp)
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

    func testGroupByAppDefaultsToOffAndDecodes() throws {
        XCTAssertFalse(Configuration().appearance.groupByApp)
        XCTAssertFalse(try decode("{}").appearance.groupByApp)
        XCTAssertFalse(try decode(#"{"appearance": {}}"#).appearance.groupByApp)
        XCTAssertTrue(try decode(#"{"appearance": {"groupByApp": true}}"#).appearance.groupByApp)
        XCTAssertFalse(try decode(#"{"appearance": {"groupByApp": "yes"}}"#).appearance.groupByApp, "bad value falls back")
        XCTAssertFalse(try decode(#"{"appearance": {"groupByApp": null}}"#).appearance.groupByApp)
        let mixed = try decode(#"{"appearance": {"groupByApp": [true], "style": "list"}}"#)
        XCTAssertFalse(mixed.appearance.groupByApp)
        XCTAssertEqual(mixed.appearance.style, .list, "one bad key does not reset its neighbours")
    }

    func testGroupByAppRoundTrips() throws {
        var c = Configuration()
        c.appearance.groupByApp = true
        let data = try JSONEncoder().encode(c)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"groupByApp\":true"))
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), c)
        XCTAssertEqual(c.validated().0, c, "validation keeps the setting")
    }

    // MARK: - Liquid Glass and preview size (v0.7)

    func testLiquidGlassDefaultsToClearAndDecodes() throws {
        XCTAssertTrue(Configuration().appearance.liquidGlass)
        XCTAssertEqual(Configuration().appearance.glassStyle, .clear)
        let empty = try decode("{}")
        XCTAssertTrue(empty.appearance.liquidGlass, "older files get the new look")
        XCTAssertEqual(empty.appearance.glassStyle, .clear)
        let set = try decode(#"{"appearance": {"liquidGlass": false, "glassStyle": "tinted"}}"#)
        XCTAssertFalse(set.appearance.liquidGlass)
        XCTAssertEqual(set.appearance.glassStyle, .tinted)
    }

    func testBadGlassValuesFallBackPerKey() throws {
        let c = try decode(#"{"appearance": {"liquidGlass": "off", "glassStyle": "frosted", "style": "list"}}"#)
        XCTAssertTrue(c.appearance.liquidGlass)
        XCTAssertEqual(c.appearance.glassStyle, .clear)
        XCTAssertEqual(c.appearance.style, .list, "one bad key does not reset its neighbours")
    }

    func testLargePreviewPercentDefaultsAndDecodes() throws {
        XCTAssertEqual(Configuration().appearance.largePreviewPercent, 66)
        XCTAssertEqual(try decode("{}").appearance.largePreviewPercent, 66)
        XCTAssertEqual(try decode(#"{"appearance": {"largePreviewPercent": 75}}"#).appearance.largePreviewPercent, 75)
        XCTAssertEqual(try decode(#"{"appearance": {"largePreviewPercent": "big"}}"#).appearance.largePreviewPercent, 66)
        XCTAssertEqual(try decode(#"{"appearance": {"largePreviewPercent": 70.5}}"#).appearance.largePreviewPercent, 66)
    }

    func testClampsLargePreviewPercent() {
        var c = Configuration()
        c.appearance.largePreviewPercent = 5
        var (valid, notes) = c.validated()
        XCTAssertEqual(valid.appearance.largePreviewPercent, 25)
        XCTAssertEqual(notes.count, 1)
        c.appearance.largePreviewPercent = 400
        (valid, notes) = c.validated()
        XCTAssertEqual(valid.appearance.largePreviewPercent, 100)
        XCTAssertEqual(notes.count, 1)
        for ok in [25, 50, 66, 75, 100] {
            c.appearance.largePreviewPercent = ok
            (valid, notes) = c.validated()
            XCTAssertEqual(valid.appearance.largePreviewPercent, ok)
            XCTAssertEqual(notes, [])
        }
    }

    func testLargePreviewScaleIsClampedFraction() {
        var a = Appearance()
        XCTAssertEqual(a.largePreviewScale, 0.66, accuracy: 1e-9)
        a.largePreviewPercent = 100
        XCTAssertEqual(a.largePreviewScale, 1)
        a.largePreviewPercent = -3
        XCTAssertEqual(a.largePreviewScale, 0.25)
        a.largePreviewPercent = Int.max
        XCTAssertEqual(a.largePreviewScale, 1)
    }

    func testGlassAndPreviewSettingsRoundTrip() throws {
        var c = Configuration()
        c.appearance.liquidGlass = false
        c.appearance.glassStyle = .tinted
        c.appearance.largePreviewPercent = 50
        let data = try JSONEncoder().encode(c)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"liquidGlass\":false"))
        XCTAssertTrue(text.contains("\"glassStyle\":\"tinted\""))
        XCTAssertTrue(text.contains("\"largePreviewPercent\":50"))
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), c)
    }

    // MARK: - Thumbnails, large preview and block positions (v0.8)

    func testThumbnailAndLargePreviewDefaultsOnAndDecode() throws {
        XCTAssertTrue(Configuration().appearance.windowThumbnails)
        XCTAssertTrue(Configuration().appearance.showLargePreview)
        let c = try decode(#"{"appearance": {"windowThumbnails": false, "showLargePreview": false}}"#)
        XCTAssertFalse(c.appearance.windowThumbnails)
        XCTAssertFalse(c.appearance.showLargePreview)
        let bad = try decode(#"{"appearance": {"windowThumbnails": "no", "showLargePreview": 3, "style": "list"}}"#)
        XCTAssertTrue(bad.appearance.windowThumbnails)
        XCTAssertTrue(bad.appearance.showLargePreview)
        XCTAssertEqual(bad.appearance.style, .list)
    }

    func testBlockPositionsDefaultToNilAndDecode() throws {
        XCTAssertNil(Configuration().appearance.panelPosition)
        XCTAssertNil(Configuration().appearance.previewPosition)
        let c = try decode(#"{"appearance": {"panelPosition": {"x": 0.3, "y": 0.8}, "previewPosition": {"x": 0.7, "y": 0.2}}}"#)
        XCTAssertEqual(c.appearance.panelPosition, BlockPosition(x: 0.3, y: 0.8))
        XCTAssertEqual(c.appearance.previewPosition, BlockPosition(x: 0.7, y: 0.2))
        let bad = try decode(#"{"appearance": {"panelPosition": {"x": "a"}, "previewPosition": 4, "size": "large"}}"#)
        XCTAssertNil(bad.appearance.panelPosition)
        XCTAssertNil(bad.appearance.previewPosition)
        XCTAssertEqual(bad.appearance.size, .large)
    }

    func testOutOfRangePositionsAreClampedSilently() {
        var c = Configuration()
        c.appearance.panelPosition = BlockPosition(x: -2, y: 7)
        c.appearance.previewPosition = BlockPosition(x: 0.4, y: 0.6)
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.appearance.panelPosition, BlockPosition(x: 0, y: 1))
        XCTAssertEqual(valid.appearance.previewPosition, BlockPosition(x: 0.4, y: 0.6))
        XCTAssertEqual(notes, [])
        XCTAssertEqual(valid.validated().0, valid)
    }

    func testPositionsRoundTripAndNilIsOmitted() throws {
        let plain = String(decoding: try JSONEncoder().encode(Configuration()), as: UTF8.self)
        XCTAssertFalse(plain.contains("panelPosition"))
        var c = Configuration()
        c.appearance.panelPosition = BlockPosition(x: 0.5, y: 0.25)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), c)
    }

    // MARK: - Color theme (v0.8)

    func testColorThemeDefaultsToNoneAndDecodesInAppearance() throws {
        XCTAssertEqual(Configuration().appearance.colorTheme, ColorTheme.none)
        XCTAssertFalse(Configuration().appearance.colorTheme.isEnabled)
        let c = try decode(##"{"appearance": {"colorTheme": {"preset": "sand", "colors": ["#c9a27e", "#d8c49a"], "intensity": 0.55, "grain": 0.3, "opacity": 0.7}}}"##)
        XCTAssertEqual(c.appearance.colorTheme.preset, "sand")
        XCTAssertEqual(c.appearance.colorTheme.opacity, 0.7)
        XCTAssertTrue(c.appearance.colorTheme.isEnabled)
    }

    func testBadColorThemeDoesNotResetItsNeighbours() throws {
        let c = try decode(#"{"appearance": {"colorTheme": 7, "style": "list"}}"#)
        XCTAssertEqual(c.appearance.colorTheme, ColorTheme.none)
        XCTAssertEqual(c.appearance.style, .list)
    }

    func testValidationCleansTheColorTheme() {
        var c = Configuration()
        c.appearance.colorTheme = ColorTheme(preset: "custom", colors: ["#ABCDEF", "nope", "#111111", "#222222", "#333333"], intensity: 4, grain: -1, opacity: 2)
        let valid = c.validated().0
        XCTAssertEqual(valid.appearance.colorTheme, c.appearance.colorTheme.validated())
        XCTAssertLessThanOrEqual(valid.appearance.colorTheme.colors.count, 3)
        XCTAssertEqual(valid.validated().0, valid)
    }

    // MARK: - v0.9 settings

    func testNewSettingsDefaults() throws {
        for c in [Configuration(), try decode("{}"), try decode(#"{"appearance": {}, "behavior": {}, "filters": {}}"#)] {
            XCTAssertTrue(c.behavior.quickSelect)
            XCTAssertTrue(c.appearance.animations)
            XCTAssertEqual(c.appearance.menuBarIconStyle, .classic)
            XCTAssertEqual(c.filters.pinnedBundleIDs, [])
            XCTAssertTrue(c.triggers.allSatisfy { $0.style == nil })
        }
        XCTAssertNil(Trigger(shortcut: .optionTab, scope: .allWindows).style)
    }

    func testMenuBarIconStyleCases() {
        XCTAssertEqual(MenuBarIconStyle.allCases.map(\.rawValue), ["classic", "filled", "minimal", "themed"])
    }

    func testQuickSelectDecodesLeniently() throws {
        XCTAssertFalse(try decode(#"{"behavior": {"quickSelect": false}}"#).behavior.quickSelect)
        XCTAssertTrue(try decode(#"{"behavior": {"quickSelect": true}}"#).behavior.quickSelect)
        let bad = try decode(#"{"behavior": {"quickSelect": "off", "wrapAround": false}}"#)
        XCTAssertTrue(bad.behavior.quickSelect, "bad value falls back")
        XCTAssertFalse(bad.behavior.wrapAround, "neighbours kept")
        XCTAssertTrue(try decode(#"{"behavior": {"quickSelect": null}}"#).behavior.quickSelect)
    }

    func testAnimationsDecodesLeniently() throws {
        XCTAssertFalse(try decode(#"{"appearance": {"animations": false}}"#).appearance.animations)
        let bad = try decode(#"{"appearance": {"animations": 0, "size": "small"}}"#)
        XCTAssertTrue(bad.appearance.animations, "bad value falls back")
        XCTAssertEqual(bad.appearance.size, .small, "neighbours kept")
    }

    func testMenuBarIconStyleDecodesLeniently() throws {
        for style in MenuBarIconStyle.allCases {
            XCTAssertEqual(try decode(#"{"appearance": {"menuBarIconStyle": "\#(style.rawValue)"}}"#).appearance.menuBarIconStyle, style)
        }
        for badValue in [#""sparkly""#, "3", "true", #"["filled"]"#, #""Filled""#] {
            let c = try decode(#"{"appearance": {"menuBarIconStyle": \#(badValue), "theme": "dark"}}"#)
            XCTAssertEqual(c.appearance.menuBarIconStyle, .classic, badValue)
            XCTAssertEqual(c.appearance.theme, .dark, "neighbours kept for \(badValue)")
        }
    }

    func testPinnedBundleIDsDecodeLeniently() throws {
        XCTAssertEqual(try decode(#"{"filters": {"pinnedBundleIDs": ["com.a", "com.b"]}}"#).filters.pinnedBundleIDs, ["com.a", "com.b"])
        XCTAssertEqual(try decode(#"{"filters": {"pinnedBundleIDs": ["com.a", 7, null, "com.b"]}}"#).filters.pinnedBundleIDs,
                       ["com.a", "com.b"], "bad elements are dropped, good ones kept")
        let bad = try decode(#"{"filters": {"pinnedBundleIDs": "com.a", "showMinimized": false}}"#)
        XCTAssertEqual(bad.filters.pinnedBundleIDs, [])
        XCTAssertFalse(bad.filters.showMinimized, "neighbours kept")
        XCTAssertEqual(FilterOptions(pinnedBundleIDs: ["x.y"]).pinnedBundleIDs, ["x.y"])
    }

    func testCleansPinnedBundleIDsLikeExcludedOnes() {
        var c = Configuration()
        c.filters.pinnedBundleIDs = ["  com.a.App ", "", "com.b", "COM.A.APP", "\n", "com.b", "\tcom.c\n"]
        c.filters.excludedBundleIDs = c.filters.pinnedBundleIDs
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.filters.pinnedBundleIDs, ["com.a.App", "com.b", "com.c"])
        XCTAssertEqual(valid.filters.pinnedBundleIDs, valid.filters.excludedBundleIDs)
        XCTAssertEqual(notes, [], "cleaning bundle IDs is silent")
        XCTAssertEqual(valid.validated().0, valid, "idempotent")
    }

    func testPinnedAndExcludedListsAreCleanedIndependently() {
        var c = Configuration()
        c.filters.pinnedBundleIDs = ["com.a", "com.A"]
        c.filters.excludedBundleIDs = ["com.b"]
        let valid = c.validated().0
        XCTAssertEqual(valid.filters.pinnedBundleIDs, ["com.a"])
        XCTAssertEqual(valid.filters.excludedBundleIDs, ["com.b"])
    }

    func testNewSettingsRoundTrip() throws {
        var c = Configuration()
        c.behavior.quickSelect = false
        c.appearance.animations = false
        c.appearance.menuBarIconStyle = .themed
        c.filters.pinnedBundleIDs = ["com.apple.Safari", "com.apple.mail"]
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows, style: .list),
            Trigger(shortcut: .optionGrave, scope: .activeApp),
            Trigger(shortcut: .commandGrave, scope: .apps, style: .grid),
        ]
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), c)
    }

    // MARK: - Per-trigger style

    func testTriggerStyleDecodes() throws {
        let c = try decode(#"{"triggers": [{"shortcut": "option+tab", "scope": "allWindows", "style": "list"}, {"shortcut": "option+grave", "scope": "activeApp"}]}"#)
        XCTAssertEqual(c.triggers, [
            Trigger(shortcut: .optionTab, scope: .allWindows, style: .list),
            Trigger(shortcut: .optionGrave, scope: .activeApp),
        ])
    }

    func testBadTriggerStyleKeepsTheTrigger() throws {
        for badValue in [#""carousel""#, "1", "null", "false", #"{"a": 1}"#, #""LIST""#] {
            let c = try decode(#"{"triggers": [{"shortcut": "cmd+tab", "scope": "apps", "style": \#(badValue)}]}"#)
            XCTAssertEqual(c.triggers, [Trigger(shortcut: .commandTab, scope: .apps)], badValue)
        }
    }

    func testTriggerStillNeedsShortcutAndScope() throws {
        let c = try decode(#"{"triggers": [{"shortcut": "hyper+tab", "scope": "apps", "style": "list"}, {"shortcut": "cmd+tab", "style": "list"}, {"scope": "apps"}, {"shortcut": "ctrl+tab", "scope": "allWindows", "style": "grid"}]}"#)
        XCTAssertEqual(c.triggers, [Trigger(shortcut: .controlTab, scope: .allWindows, style: .grid)])
    }

    func testTriggerStyleIsOnlyEncodedWhenSet() throws {
        let plain = try JSONEncoder().encode(Trigger(shortcut: .optionTab, scope: .allWindows))
        let plainObject = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        XCTAssertEqual(Set(plainObject.keys), ["shortcut", "scope"])

        let styled = try JSONEncoder().encode(Trigger(shortcut: .optionTab, scope: .allWindows, style: .list))
        let styledObject = try XCTUnwrap(JSONSerialization.jsonObject(with: styled) as? [String: Any])
        XCTAssertEqual(styledObject["style"] as? String, "list")
        XCTAssertEqual(styledObject["shortcut"] as? String, "option+tab")
        XCTAssertEqual(styledObject["scope"] as? String, "allWindows")
    }

    func testValidationKeepsTriggerStyles() {
        var c = Configuration()
        c.triggers = [Trigger(shortcut: .optionTab, scope: .allWindows, style: .list), Trigger(shortcut: .commandGrave, scope: .apps, style: .grid)]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, c.triggers)
        XCTAssertEqual(notes, [])
    }

    func testDuplicateShortcutsWithDifferentStylesAreStillDuplicates() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows, style: .list),
            Trigger(shortcut: .optionTab, scope: .allWindows, style: .grid),
            Trigger(shortcut: .optionTab, scope: .allWindows),
        ]
        let (valid, notes) = c.validated()
        XCTAssertEqual(valid.triggers, [Trigger(shortcut: .optionTab, scope: .allWindows, style: .list)])
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.allSatisfy { $0.contains("twice") })
    }

    func testTriggerMatchingReturnsTheStyle() {
        var c = Configuration()
        c.triggers = [Trigger(shortcut: .optionTab, scope: .allWindows, style: .list)]
        XCTAssertEqual(c.trigger(matching: .optionTab)?.style, .list)
    }

    func testEffectiveAppearanceForTrigger() {
        var appearance = Appearance()
        appearance.style = .grid
        appearance.size = .large
        appearance.showPreviews = true
        appearance.animations = false

        let plain = Trigger(shortcut: .optionTab, scope: .allWindows)
        XCTAssertEqual(appearance.effective(for: plain), appearance)

        let list = Trigger(shortcut: .optionTab, scope: .allWindows, style: .list)
        var expected = appearance
        expected.style = .list
        XCTAssertEqual(appearance.effective(for: list), expected, "only the style changes")

        let grid = Trigger(shortcut: .optionTab, scope: .allWindows, style: .grid)
        XCTAssertEqual(appearance.effective(for: grid), appearance)

        appearance.style = .list
        XCTAssertEqual(appearance.effective(for: grid).style, .grid)
        XCTAssertEqual(appearance.effective(for: plain).style, .list)
    }
}
