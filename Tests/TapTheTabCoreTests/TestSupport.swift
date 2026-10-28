import Foundation
@testable import TapTheTabCore

/// Builds a window item with sensible defaults so tests only spell out what matters.
func window(
    _ number: UInt32,
    pid: Int32 = 100,
    app: String = "App",
    bundle: String? = nil,
    title: String = "",
    minimized: Bool = false,
    hidden: Bool = false,
    fullscreen: Bool = false,
    onActiveSpace: Bool = true,
    display: UInt32? = nil
) -> SwitcherItem {
    SwitcherItem(
        id: .window(number),
        pid: pid,
        appName: app,
        bundleID: bundle,
        title: title,
        isMinimized: minimized,
        isAppHidden: hidden,
        isFullscreen: fullscreen,
        isOnActiveSpace: onActiveSpace,
        displayID: display
    )
}

/// Builds a windowless app entry.
func windowlessApp(pid: Int32, app: String = "App", bundle: String? = nil, hidden: Bool = false) -> SwitcherItem {
    SwitcherItem(id: .app(pid: pid), pid: pid, appName: app, bundleID: bundle, isAppHidden: hidden)
}

/// Characters of `string` at `indices`, joined, for readable highlight assertions.
func characters(of string: String, at indices: [Int]) -> String {
    let chars = Array(string)
    return String(indices.map { chars[$0] })
}
