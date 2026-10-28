import AppKit
import ApplicationServices
import TapTheTabCore

/// Enumerates windows of running apps via the window server and the Accessibility API.
///
/// Enumeration runs off the main thread (AX calls are blocking IPC to every app) and
/// results are delivered on the main thread. The last snapshot is kept so the switcher
/// can open instantly and refresh in place.
final class WindowCatalog {
    struct Snapshot {
        var items: [SwitcherItem] = []
        var elements: [ItemID: AXUIElement] = [:]
        var date = Date.distantPast
    }

    private struct AppInfo {
        let pid: pid_t
        let name: String
        let bundleID: String?
        let isHidden: Bool
    }

    private struct ScreenInfo {
        let id: UInt32
        let frame: CGRect
    }

    private struct Found {
        var item: SwitcherItem
        var element: AXUIElement?
        var order: Int
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [[Found]]
        init(count: Int) { storage = Array(repeating: [], count: count) }
        func set(_ value: [Found], at index: Int) {
            lock.lock()
            storage[index] = value
            lock.unlock()
        }
        var all: [Found] {
            lock.lock()
            defer { lock.unlock() }
            return storage.flatMap { $0 }
        }
    }

    private let queue = DispatchQueue(label: "io.github.memoliertorerr.TapTheTab.catalog", qos: .userInteractive)
    private var pendingCompletions: [(Snapshot) -> Void] = []
    private var isRefreshing = false
    private var refreshAgain = false

    /// Main-thread only.
    private(set) var latest = Snapshot()

    /// Main-thread only.
    func element(for id: ItemID) -> AXUIElement? { latest.elements[id] }

    /// Re-enumerate. Overlapping calls are coalesced; every completion gets called once
    /// with a snapshot taken after it was requested. Main-thread only.
    func refresh(completion: ((Snapshot) -> Void)? = nil) {
        if let completion { pendingCompletions.append(completion) }
        if isRefreshing {
            refreshAgain = true
            return
        }
        isRefreshing = true
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated }
            .map { AppInfo(pid: $0.processIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "App", bundleID: $0.bundleIdentifier, isHidden: $0.isHidden) }
        let screens = NSScreen.screens.compactMap { screen -> ScreenInfo? in
            guard let id = screen.displayID else { return nil }
            return ScreenInfo(id: id, frame: screen.topLeftFrame)
        }
        let completions = pendingCompletions
        pendingCompletions = []

        queue.async { [weak self] in
            let snapshot = WindowCatalog.enumerate(apps: apps, screens: screens)
            DispatchQueue.main.async {
                guard let self else { return }
                self.latest = snapshot
                self.isRefreshing = false
                completions.forEach { $0(snapshot) }
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    // MARK: - Enumeration (background queue)

    private static func enumerate(apps: [AppInfo], screens: [ScreenInfo]) -> Snapshot {
        // Front-to-back order of on-screen windows on the current Space(s).
        var zOrder: [CGWindowID: Int] = [:]
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for (index, info) in list.enumerated() {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let number = info[kCGWindowNumber as String] as? Int else { continue }
                zOrder[CGWindowID(number)] = index
            }
        }

        let results = Results(count: apps.count)

        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            let appElement = AX.application(app.pid)
            var found: [Found] = []
            for window in AX.elements(appElement, kAXWindowsAttribute) {
                guard isSwitchable(window), let windowID = AX.windowID(window) else { continue }
                let minimized = AX.bool(window, kAXMinimizedAttribute) ?? false
                let fullscreen = AX.bool(window, AX.fullScreenAttribute) ?? false
                let title = AX.string(window, kAXTitleAttribute) ?? ""
                let onScreen = zOrder[windowID] != nil
                let item = SwitcherItem(
                    id: .window(windowID),
                    pid: app.pid,
                    appName: app.name,
                    bundleID: app.bundleID,
                    title: title,
                    isMinimized: minimized,
                    isAppHidden: app.isHidden,
                    isFullscreen: fullscreen,
                    isOnActiveSpace: onScreen,
                    displayID: AX.frame(window).flatMap { display(for: $0, screens: screens) }
                )
                // On-screen windows keep z-order; the rest go after, grouped by app.
                let order = zOrder[windowID] ?? (100_000 + index * 100 + found.count)
                found.append(Found(item: item, element: window, order: order))
            }
            if found.isEmpty {
                let item = SwitcherItem(id: .app(pid: app.pid), pid: app.pid, appName: app.name, bundleID: app.bundleID, isAppHidden: app.isHidden)
                found.append(Found(item: item, element: nil, order: 200_000 + index))
            }
            results.set(found, at: index)
        }

        let all = results.all.sorted { $0.order < $1.order }
        var snapshot = Snapshot()
        snapshot.items = all.map(\.item)
        for entry in all {
            if let element = entry.element { snapshot.elements[entry.item.id] = element }
        }
        snapshot.date = Date()
        return snapshot
    }

    /// Standard windows and dialogs only; skips panels, popovers, tooltips and sheets.
    private static func isSwitchable(_ window: AXUIElement) -> Bool {
        guard AX.string(window, kAXRoleAttribute) == kAXWindowRole else { return false }
        let subrole = AX.string(window, kAXSubroleAttribute)
        return subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }

    private static func display(for frame: CGRect, screens: [ScreenInfo]) -> UInt32? {
        var best: (id: UInt32, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.area { best = (screen.id, area) }
        }
        return best?.id
    }
}
