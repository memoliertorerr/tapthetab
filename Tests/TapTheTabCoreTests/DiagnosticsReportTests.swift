import XCTest
@testable import TapTheTabCore

final class DiagnosticsReportTests: XCTestCase {
    private func report(_ configuration: Configuration = Configuration()) -> DiagnosticsReport {
        DiagnosticsReport(
            appVersion: "0.3.0",
            build: "42",
            osVersion: "14.5 (23F79)",
            architecture: "arm64",
            accessibilityGranted: true,
            screenRecordingGranted: false,
            windowCount: 12,
            appCount: 5,
            watchedAppCount: 4,
            configuration: configuration
        )
    }

    func testDefaultConfigurationFormatIsPinned() {
        let expected = """
        ### TapTheTab diagnostics

        ```text
        TapTheTab: 0.3.0 (42)
        macOS: 14.5 (23F79)
        Architecture: arm64

        Permissions
          Accessibility: granted
          Screen Recording: not granted

        Catalog
          Windows: 12
          Apps: 5
          Watched apps: 4
          Last full refresh: unknown
          Last partial refresh: unknown
          Skipped windows: unknown

        Private APIs
          List other Spaces: unknown
          Focus across Spaces: unknown
          Missing symbols: unknown
          Last switch: none yet

        Triggers (2)
          ⌥⇥  option+tab  allWindows
          ⌥`  option+`  activeApp

        Appearance
          style: grid
          size: medium
          showPreviews: false
          windowThumbnails: true
          showLargePreview: true
          largePreviewPercent: 66
          panelPosition: default
          previewPosition: default
          showAppName: true
          groupByApp: false
          showMenuBarIcon: true
          menuBarIconStyle: classic
          theme: system
          liquidGlass: true
          glassStyle: clear
          colorTheme: none
          placement: mouse
          showDelayMilliseconds: 90
          animations: true

        Behavior
          releaseToSwitch: true
          searchEnabled: true
          startOnPrevious: true
          mouseHoverSelects: true
          wrapAround: true
          quickSelect: true
          checkForUpdates: false

        Filters
          showMinimized: true
          showHiddenApps: true
          showWindowlessApps: false
          currentSpaceOnly: false
          currentDisplayOnly: false
          currentDisplayFirst: false
          showOtherSpaces: false
          excludedApps: 0
          pinnedApps: 0

        Config version: 1
        ```

        """
        XCTAssertEqual(report().markdown, expected)
    }

    func testCustomConfigurationIsReflected() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: .commandTab, scope: .apps),
            Trigger(shortcut: Shortcut(keyCode: KeyCode.grave, modifiers: [.control, .shift]), scope: .activeApp),
        ]
        c.appearance.style = .list
        c.appearance.size = .large
        c.appearance.showPreviews = true
        c.appearance.showAppName = false
        c.appearance.groupByApp = true
        c.appearance.theme = .dark
        c.appearance.liquidGlass = false
        c.appearance.glassStyle = .tinted
        c.appearance.colorTheme = ColorTheme.none.applying(ThemePreset.named("dusk")!)
        c.appearance.largePreviewPercent = 75
        c.appearance.windowThumbnails = false
        c.appearance.showLargePreview = false
        c.appearance.panelPosition = BlockPosition(x: 0.2, y: 0.9)
        c.appearance.placement = .activeWindow
        c.appearance.showDelayMilliseconds = 0
        c.behavior.releaseToSwitch = false
        c.behavior.searchEnabled = false
        c.behavior.startOnPrevious = false
        c.behavior.mouseHoverSelects = false
        c.behavior.wrapAround = false
        c.filters.showMinimized = false
        c.filters.showHiddenApps = false
        c.filters.showWindowlessApps = true
        c.filters.currentSpaceOnly = true
        c.filters.currentDisplayOnly = true
        c.filters.showOtherSpaces = true

        let markdown = report(c).markdown
        for line in [
            "Triggers (2)", "  ⌘⇥  command+tab  apps", "  ⌃⇧`  control+shift+`  activeApp",
            "  style: list", "  size: large", "  showPreviews: true", "  showAppName: false", "  groupByApp: true",
            "  theme: dark", "  liquidGlass: false", "  glassStyle: tinted", "  colorTheme: dusk", "  largePreviewPercent: 75",
            "  windowThumbnails: false", "  showLargePreview: false", "  panelPosition: moved", "  previewPosition: default",
            "  placement: activeWindow", "  showDelayMilliseconds: 0",
            "  releaseToSwitch: false", "  searchEnabled: false", "  startOnPrevious: false",
            "  mouseHoverSelects: false", "  wrapAround: false",
            "  showMinimized: false", "  showHiddenApps: false", "  showWindowlessApps: true",
            "  currentSpaceOnly: true", "  currentDisplayOnly: true", "  showOtherSpaces: true",
        ] {
            XCTAssertTrue(markdown.components(separatedBy: "\n").contains(line), "missing line: \(line)")
        }
    }

    func testExcludedAppsAreCountedNeverListed() {
        var c = Configuration()
        c.filters.excludedBundleIDs = ["com.secret.Diary", "org.example.PrivateThing", "com.bank.app"]
        let markdown = report(c).markdown
        XCTAssertTrue(markdown.contains("  excludedApps: 3\n"))
        for id in c.filters.excludedBundleIDs {
            XCTAssertFalse(markdown.contains(id), id)
            XCTAssertFalse(markdown.lowercased().contains(id.lowercased()), id)
        }
        for fragment in ["secret", "Diary", "PrivateThing", "bank"] {
            XCTAssertFalse(markdown.contains(fragment), fragment)
        }
    }

    func testOnlyExcludedAppsDifferenceIsTheCount() {
        var a = Configuration()
        a.filters.excludedBundleIDs = ["com.one.app", "com.two.app"]
        var b = Configuration()
        b.filters.excludedBundleIDs = ["x.y", "z.w"]
        XCTAssertEqual(report(a).markdown, report(b).markdown)
    }

    func testDeterministic() {
        XCTAssertEqual(report().markdown, report().markdown)
    }

    func testNoTriggers() {
        var c = Configuration()
        c.triggers = []
        let markdown = report(c).markdown
        XCTAssertTrue(markdown.contains("Triggers (0)\n\nAppearance\n"))
    }

    func testPermissionsAndCounts() {
        var r = report()
        r.accessibilityGranted = false
        r.screenRecordingGranted = true
        r.windowCount = 0
        r.appCount = 1
        r.watchedAppCount = 0
        let markdown = r.markdown
        XCTAssertTrue(markdown.contains("  Accessibility: not granted\n  Screen Recording: granted\n"))
        XCTAssertTrue(markdown.contains("  Windows: 0\n  Apps: 1\n  Watched apps: 0\n"))
    }

    func testPrivateAPIStatus() {
        var r = report()
        r.otherSpacesListingAvailable = true
        r.focusAcrossSpacesAvailable = false
        r.missingPrivateSymbols = ["GetProcessForPID", "SLPSPostEventRecordTo"]
        XCTAssertTrue(r.markdown.contains(
            "Private APIs\n  List other Spaces: available\n  Focus across Spaces: unavailable\n"
                + "  Missing symbols: GetProcessForPID, SLPSPostEventRecordTo\n  Last switch: none yet\n\n"))

        r.missingPrivateSymbols = []
        r.focusAcrossSpacesAvailable = true
        XCTAssertTrue(r.markdown.contains("  Focus across Spaces: available\n  Missing symbols: none\n"))
    }

    func testPrivateAPIStatusThroughInitializer() {
        let r = DiagnosticsReport(
            appVersion: "1", build: "1", osVersion: "15", architecture: "arm64",
            accessibilityGranted: true, screenRecordingGranted: true,
            windowCount: 0, appCount: 0, watchedAppCount: 0, configuration: Configuration(),
            otherSpacesListingAvailable: false, focusAcrossSpacesAvailable: true, missingPrivateSymbols: ["A\n```"]
        )
        let lines = r.markdown.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("  List other Spaces: unavailable"))
        XCTAssertTrue(lines.contains("  Focus across Spaces: available"))
        XCTAssertTrue(lines.contains("  Missing symbols: A"), "names are cleaned like other free text")
        XCTAssertEqual(lines.filter { $0.hasPrefix("```") }.count, 2)
    }

    func testFreeTextFieldsCannotBreakTheReport() {
        var r = report()
        r.appVersion = "1.0\n```\n# injected"
        r.build = "\u{202E}7\u{0}"
        r.osVersion = "   "
        r.architecture = String(repeating: "x", count: 500)
        let markdown = r.markdown
        let lines = markdown.components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("```") }.count, 2, "only the report's own fence")
        XCTAssertTrue(lines.contains("TapTheTab: 1.0# injected (7)"))
        XCTAssertTrue(lines.contains("macOS: unknown"))
        XCTAssertTrue(lines.contains("Architecture: " + String(repeating: "x", count: DiagnosticsReport.maximumFieldLength)))
        XCTAssertFalse(markdown.contains("\u{202E}"))
        XCTAssertFalse(markdown.contains("\u{0}"))
    }

    func testEndsWithClosingFenceAndNewline() {
        let markdown = report().markdown
        XCTAssertTrue(markdown.hasPrefix("### TapTheTab diagnostics\n\n```text\n"))
        XCTAssertTrue(markdown.hasSuffix("\n```\n"))
    }

    func testEquatable() {
        XCTAssertEqual(report(), report())
        var other = report()
        other.build = "43"
        XCTAssertNotEqual(report(), other)
    }

    func testRefreshTimingsAreReported() {
        var report = DiagnosticsReport(
            appVersion: "1", build: "1", osVersion: "14", architecture: "arm64",
            accessibilityGranted: true, screenRecordingGranted: false,
            windowCount: 3, appCount: 2, watchedAppCount: 2, configuration: Configuration(),
            lastFullRefreshMilliseconds: 42, lastPartialRefreshMilliseconds: 3)
        XCTAssertTrue(report.markdown.contains("  Last full refresh: 42 ms\n  Last partial refresh: 3 ms\n"))
        report.lastFullRefreshMilliseconds = -5
        XCTAssertTrue(report.markdown.contains("  Last full refresh: 0 ms\n"))
    }

    func testSkippedWindowsAreSortedAndSanitized() {
        let report = DiagnosticsReport(
            appVersion: "1", build: "1", osVersion: "14", architecture: "arm64",
            accessibilityGranted: true, screenRecordingGranted: false,
            windowCount: 3, appCount: 2, watchedAppCount: 2, configuration: Configuration(),
            skippedWindowsBySubrole: ["AXUnknown": 1, "AXFloatingWindow": 4, "SecretPanel": 2, "My Panel": 3, "AXSheet": 0])
        XCTAssertTrue(report.markdown.contains("  Skipped windows: AXFloatingWindow 4, AXUnknown 1, other 5\n"))
        XCTAssertFalse(report.markdown.contains("SecretPanel"))
    }

    func testLastSwitchMethodIsReportedAndCleaned() {
        var r = report()
        r.lastSwitchMethod = "window server, status 0"
        XCTAssertTrue(r.markdown.components(separatedBy: "\n").contains("  Last switch: window server, status 0"))
        r.lastSwitchMethod = "public\nfallback`"
        XCTAssertTrue(r.markdown.components(separatedBy: "\n").contains("  Last switch: publicfallback"))
    }

    // MARK: - v0.9 settings

    func testNewSettingsAreReported() {
        var c = Configuration()
        c.triggers = [
            Trigger(shortcut: .optionTab, scope: .allWindows, style: .list),
            Trigger(shortcut: .optionGrave, scope: .activeApp),
            Trigger(shortcut: .commandGrave, scope: .apps, style: .grid),
        ]
        c.appearance.menuBarIconStyle = .minimal
        c.appearance.animations = false
        c.behavior.quickSelect = false
        c.filters.pinnedBundleIDs = ["com.a", "com.b"]
        let lines = report(c).markdown.components(separatedBy: "\n")
        for line in [
            "Triggers (3)",
            "  ⌥⇥  option+tab  allWindows  list",
            "  ⌥`  option+`  activeApp",
            "  ⌘`  command+`  apps  grid",
            "  menuBarIconStyle: minimal",
            "  animations: false",
            "  quickSelect: false",
            "  pinnedApps: 2",
        ] {
            XCTAssertTrue(lines.contains(line), "missing line: \(line)")
        }
    }

    func testPinnedAppsAreCountedNeverListed() {
        var c = Configuration()
        c.filters.pinnedBundleIDs = ["com.secret.Diary", "org.example.PrivateThing"]
        let markdown = report(c).markdown
        XCTAssertTrue(markdown.contains("  excludedApps: 0\n  pinnedApps: 2\n"))
        for fragment in ["secret", "Diary", "PrivateThing", "example"] {
            XCTAssertFalse(markdown.contains(fragment), fragment)
        }
        var other = Configuration()
        other.filters.pinnedBundleIDs = ["x.y", "z.w"]
        XCTAssertEqual(report(c).markdown, report(other).markdown, "only the count shows")
    }

    // MARK: - v0.10 settings

    func testV010SettingsAreReported() {
        var c = Configuration()
        let defaults = report(c).markdown
        XCTAssertTrue(defaults.contains("  quickSelect: true\n  checkForUpdates: false\n\nFilters\n"))
        XCTAssertTrue(defaults.contains("  currentDisplayOnly: false\n  currentDisplayFirst: false\n  showOtherSpaces: false\n"))

        c.behavior.checkForUpdates = true
        c.filters.currentDisplayFirst = true
        let lines = report(c).markdown.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("  checkForUpdates: true"))
        XCTAssertTrue(lines.contains("  currentDisplayFirst: true"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("  checkForUpdates:") }.count, 1)
        XCTAssertEqual(lines.filter { $0.hasPrefix("  currentDisplayFirst:") }.count, 1)
    }
}
