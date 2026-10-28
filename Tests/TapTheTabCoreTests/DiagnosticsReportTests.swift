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

        Triggers (2)
          ⌥⇥  option+tab  allWindows
          ⌥`  option+`  activeApp

        Appearance
          style: grid
          size: medium
          showPreviews: false
          showAppName: true
          theme: system
          placement: mouse
          showDelayMilliseconds: 90

        Behavior
          releaseToSwitch: true
          searchEnabled: true
          startOnPrevious: true
          mouseHoverSelects: true
          wrapAround: true

        Filters
          showMinimized: true
          showHiddenApps: true
          showWindowlessApps: false
          currentSpaceOnly: false
          currentDisplayOnly: false
          excludedApps: 0

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
        c.appearance.theme = .dark
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

        let markdown = report(c).markdown
        for line in [
            "Triggers (2)", "  ⌘⇥  command+tab  apps", "  ⌃⇧`  control+shift+`  activeApp",
            "  style: list", "  size: large", "  showPreviews: true", "  showAppName: false",
            "  theme: dark", "  placement: activeWindow", "  showDelayMilliseconds: 0",
            "  releaseToSwitch: false", "  searchEnabled: false", "  startOnPrevious: false",
            "  mouseHoverSelects: false", "  wrapAround: false",
            "  showMinimized: false", "  showHiddenApps: false", "  showWindowlessApps: true",
            "  currentSpaceOnly: true", "  currentDisplayOnly: true",
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
}
