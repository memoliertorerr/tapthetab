import Foundation

/// Facts for a bug report, rendered as Markdown the user can paste into a GitHub issue.
///
/// Holds no personal data by construction: no window titles, no app names, no bundle IDs
/// (excluded apps are reported only as a count), no paths and no user names. The output is
/// deterministic: fixed key order and fixed wording, never localized.
public struct DiagnosticsReport: Equatable, Sendable {
    public var appVersion: String
    public var build: String
    public var osVersion: String
    public var architecture: String
    public var accessibilityGranted: Bool
    public var screenRecordingGranted: Bool
    public var windowCount: Int
    public var appCount: Int
    public var watchedAppCount: Int
    public var configuration: Configuration

    public init(
        appVersion: String,
        build: String,
        osVersion: String,
        architecture: String,
        accessibilityGranted: Bool,
        screenRecordingGranted: Bool,
        windowCount: Int,
        appCount: Int,
        watchedAppCount: Int,
        configuration: Configuration
    ) {
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.architecture = architecture
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
        self.windowCount = windowCount
        self.appCount = appCount
        self.watchedAppCount = watchedAppCount
        self.configuration = configuration
    }

    /// Longest free-text value (versions, architecture) kept in the report.
    static let maximumFieldLength = 80

    /// Markdown suitable for pasting into a GitHub issue: a heading and one fenced text
    /// block of `key: value` lines, ending with a newline.
    public var markdown: String {
        let c = configuration
        var lines: [String] = []
        lines.append("### TapTheTab diagnostics")
        lines.append("")
        lines.append("```text")
        lines.append("TapTheTab: \(Self.clean(appVersion)) (\(Self.clean(build)))")
        lines.append("macOS: \(Self.clean(osVersion))")
        lines.append("Architecture: \(Self.clean(architecture))")
        lines.append("")
        lines.append("Permissions")
        lines.append("  Accessibility: \(Self.granted(accessibilityGranted))")
        lines.append("  Screen Recording: \(Self.granted(screenRecordingGranted))")
        lines.append("")
        lines.append("Catalog")
        lines.append("  Windows: \(windowCount)")
        lines.append("  Apps: \(appCount)")
        lines.append("  Watched apps: \(watchedAppCount)")
        lines.append("")
        lines.append("Triggers (\(c.triggers.count))")
        for trigger in c.triggers {
            lines.append("  \(trigger.shortcut.displayString)  \(trigger.shortcut.stringValue)  \(trigger.scope.rawValue)")
        }
        lines.append("")
        lines.append("Appearance")
        lines.append("  style: \(c.appearance.style.rawValue)")
        lines.append("  size: \(c.appearance.size.rawValue)")
        lines.append("  showPreviews: \(c.appearance.showPreviews)")
        lines.append("  showAppName: \(c.appearance.showAppName)")
        lines.append("  theme: \(c.appearance.theme.rawValue)")
        lines.append("  placement: \(c.appearance.placement.rawValue)")
        lines.append("  showDelayMilliseconds: \(c.appearance.showDelayMilliseconds)")
        lines.append("")
        lines.append("Behavior")
        lines.append("  releaseToSwitch: \(c.behavior.releaseToSwitch)")
        lines.append("  searchEnabled: \(c.behavior.searchEnabled)")
        lines.append("  startOnPrevious: \(c.behavior.startOnPrevious)")
        lines.append("  mouseHoverSelects: \(c.behavior.mouseHoverSelects)")
        lines.append("  wrapAround: \(c.behavior.wrapAround)")
        lines.append("")
        lines.append("Filters")
        lines.append("  showMinimized: \(c.filters.showMinimized)")
        lines.append("  showHiddenApps: \(c.filters.showHiddenApps)")
        lines.append("  showWindowlessApps: \(c.filters.showWindowlessApps)")
        lines.append("  currentSpaceOnly: \(c.filters.currentSpaceOnly)")
        lines.append("  currentDisplayOnly: \(c.filters.currentDisplayOnly)")
        lines.append("  excludedApps: \(c.filters.excludedBundleIDs.count)")
        lines.append("")
        lines.append("Config version: \(c.version)")
        lines.append("```")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func granted(_ value: Bool) -> String {
        value ? "granted" : "not granted"
    }

    /// One line of plain text: control characters and backticks removed (so a value can
    /// neither break a line nor close the code fence), trimmed, bounded, "unknown" if empty.
    static func clean(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: value.unicodeScalars.lazy.filter { scalar in
            !(scalar.properties.generalCategory == .control
                || scalar.properties.generalCategory == .lineSeparator
                || scalar.properties.generalCategory == .paragraphSeparator
                || scalar.properties.generalCategory == .format
                || scalar == "`")
        })
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        let bounded = String(trimmed.prefix(maximumFieldLength)).trimmingCharacters(in: .whitespaces)
        return bounded.isEmpty ? "unknown" : bounded
    }
}
