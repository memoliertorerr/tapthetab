import AppKit
import ApplicationServices
import TapTheTabCore

/// Enumerates windows of running apps via the window server and the Accessibility API.
///
/// Enumeration runs off the main thread (AX calls are blocking IPC to every app) and
/// results are delivered on the main thread. The last snapshot is kept so the switcher
/// can open instantly and refresh in place.
///
/// With `includesOtherSpaces`, windows on other Spaces (which the Accessibility API does
/// not report for most apps) are added from the window server's per-Space lists; see
/// `otherSpaceWindows`.
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

    /// What the Accessibility pass found for one app.
    private struct AppResult {
        var found: [Found] = []
        /// IDs of windows the app reported but that are not switchable (panels, sheets…),
        /// so the other-Spaces pass doesn't bring them back. Only collected for that pass.
        var ignoredWindowIDs: [CGWindowID] = []
        /// The app didn't answer within the AX timeout.
        var isBusy = false
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AppResult]
        init(count: Int) { storage = Array(repeating: AppResult(), count: count) }
        func set(_ value: AppResult, at index: Int) {
            lock.lock()
            storage[index] = value
            lock.unlock()
        }
        var all: [AppResult] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    /// Upper bound for the other-Spaces pass of one refresh; what was found by then is used.
    private static let otherSpacesBudgetNanoseconds: UInt64 = 150_000_000
    /// `CGSCopyWindowsWithOptionsAndTags` options: 0x2 lists the Space's ordinary windows
    /// without minimized ones (those still come from the Accessibility API).
    private static let otherSpacesListOptions: UInt32 = 0x2
    /// Sort keys: on-screen windows use their z-order (< 100_000), the app's other
    /// Accessibility windows 100_000 + app × 100, windowless apps 200_000 + app. Windows
    /// on other Spaces sit between the last two, in `OtherSpaceWindows.select` order.
    private static let otherSpacesOrder = 150_000

    private let queue = DispatchQueue(label: "io.github.memoliertorerr.TapTheTab.catalog", qos: .userInteractive)
    private var pendingCompletions: [(Snapshot) -> Void] = []
    private var isRefreshing = false
    private var refreshAgain = false

    /// Main-thread only.
    private(set) var latest = Snapshot()

    /// Also list windows on other Spaces (Settings → Filters). Takes effect from the next
    /// refresh, and only when the private window-server functions resolved. Main-thread only.
    var includesOtherSpaces = false

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
        // The window server's connection for this process; nil skips the other-Spaces pass.
        let connection: Int32? = includesOtherSpaces ? Self.otherSpacesConnection() : nil

        let previous = latest
        queue.async { [weak self] in
            let snapshot = WindowCatalog.enumerate(apps: apps, screens: screens, previous: previous, otherSpacesConnection: connection)
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

    private static func enumerate(apps: [AppInfo], screens: [ScreenInfo], previous: Snapshot, otherSpacesConnection: Int32?) -> Snapshot {
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
        // Windows from the last snapshot, per app, for apps too busy to answer this time.
        var previousByPID: [pid_t: [SwitcherItem]] = [:]
        for item in previous.items where !item.isWindowless {
            previousByPID[item.pid, default: []].append(item)
        }

        let collectsIgnoredWindows = otherSpacesConnection != nil
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            let appElement = AX.application(app.pid)
            var found: [Found] = []
            var ignored: [CGWindowID] = []
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
            if status == .cannotComplete, let kept = previousByPID[app.pid], !kept.isEmpty {
                // The app didn't answer within the timeout (busy, beachballing). Keep its
                // windows as last seen rather than making them vanish from the switcher.
                for (offset, original) in kept.enumerated() {
                    var item = original
                    item.isAppHidden = app.isHidden
                    guard case .window(let number) = item.id else { continue }
                    item.isOnActiveSpace = zOrder[number] != nil
                    let order = zOrder[number] ?? (100_000 + index * 100 + offset)
                    found.append(Found(item: item, element: previous.elements[item.id], order: order))
                }
                results.set(AppResult(found: found, isBusy: true), at: index)
                return
            }
            let windows: [AXUIElement] = status == .success ? ((value as? [AXUIElement]) ?? []) : []
            for window in windows {
                guard isSwitchable(window) else {
                    if collectsIgnoredWindows, let id = AX.windowID(window) { ignored.append(id) }
                    continue
                }
                guard let windowID = AX.windowID(window) else { continue }
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
            results.set(AppResult(found: found, ignoredWindowIDs: ignored, isBusy: status == .cannotComplete), at: index)
        }

        let appResults = results.all
        var entries = appResults.flatMap(\.found)
        if let connection = otherSpacesConnection {
            // Everything already known (on screen, found through AX, or deliberately
            // skipped by AX) stays as it is; the window server only adds what is missing.
            var known = Set(zOrder.keys)
            var busy = Set<pid_t>()
            for (index, result) in appResults.enumerated() {
                for entry in result.found {
                    if case .window(let number) = entry.item.id { known.insert(number) }
                }
                known.formUnion(result.ignoredWindowIDs)
                if result.isBusy { busy.insert(apps[index].pid) }
            }
            let extra = otherSpaceWindows(connection: connection, apps: apps, screens: screens, known: known, busy: busy, previous: previous)
            if !extra.isEmpty {
                // An app whose only windows are on other Spaces is not windowless.
                let pids = Set(extra.map(\.item.pid))
                entries.removeAll { $0.item.isWindowless && pids.contains($0.item.pid) }
                entries.append(contentsOf: extra)
            }
        }

        let all = entries.sorted { $0.order < $1.order }
        var snapshot = Snapshot()
        snapshot.items = all.map(\.item)
        for entry in all {
            if let element = entry.element { snapshot.elements[entry.item.id] = element }
        }
        snapshot.date = Date()
        return snapshot
    }

    // MARK: - Other Spaces (background queue)

    /// Windows on Spaces that are not shown right now, including fullscreen Spaces, which
    /// the Accessibility API doesn't report. Listed by the window server per Space,
    /// filtered with the public window descriptions, and given the element and title from
    /// the previous snapshot when the window was seen before (for example while the user
    /// was on its Space; such elements usually stay valid). Without one, the item has no
    /// element: focusing it goes through `WindowActions.activate(acrossSpaces:)` and the
    /// other actions are refused. Windows of hidden apps are left out.
    ///
    /// Fails soft: any unexpected answer yields fewer windows, and once the time budget is
    /// spent the pass stops with what it has.
    private static func otherSpaceWindows(
        connection: Int32,
        apps: [AppInfo],
        screens: [ScreenInfo],
        known: Set<CGWindowID>,
        busy: Set<pid_t>,
        previous: Snapshot
    ) -> [Found] {
        guard let copySpaces = PrivateAPI.cgsCopyManagedDisplaySpaces,
              let copyWindows = PrivateAPI.cgsCopyWindowsWithOptionsAndTags else { return [] }
        let deadline = DispatchTime.now().uptimeNanoseconds + otherSpacesBudgetNanoseconds
        func outOfTime() -> Bool { DispatchTime.now().uptimeNanoseconds > deadline }

        // +1 reference, released by takeRetainedValue.
        guard let displayList = copySpaces(connection)?.takeRetainedValue(),
              let displays = displayList as? [[String: Any]] else { return [] }
        let spaces = SpaceLayout.spaces(fromManagedDisplaySpaces: displays)
        guard spaces.contains(where: { !$0.isCurrent }) else { return [] }

        var windowIDsBySpace: [[UInt32]] = []
        for space in spaces {
            if outOfTime() {
                Log.windows.debug("Other Spaces: time budget spent after \(windowIDsBySpace.count, privacy: .public) of \(spaces.count, privacy: .public) Spaces")
                break
            }
            windowIDsBySpace.append(windowIDs(onSpace: space.id, connection: connection, copyWindows: copyWindows))
        }
        let candidates = OtherSpaceWindows.candidates(spaces: spaces, windowIDsBySpace: windowIDsBySpace, excluding: known)
        guard !candidates.isEmpty, !outOfTime() else { return [] }

        var appOrder: [Int32: Int] = [:]
        var appsByPID: [pid_t: AppInfo] = [:]
        for (index, app) in apps.enumerated() where !app.isHidden {
            appOrder[app.pid] = index
            appsByPID[app.pid] = app
        }
        let described = describe(candidates.map(\.windowID))
        let selected = OtherSpaceWindows.select(candidates, descriptions: described.windows, appOrder: appOrder)

        var previousTitles: [ItemID: String] = [:]
        for item in previous.items { previousTitles[item.id] = item.title }

        var found: [Found] = []
        for (rank, candidate) in selected.enumerated() {
            guard let window = described.windows[candidate.windowID], let app = appsByPID[window.pid] else { continue }
            let id = ItemID.window(candidate.windowID)
            var element = previous.elements[id]
            var accessibilityTitle: String?
            // One AX call per remembered window, skipped for apps that just timed out.
            if let remembered = element, !busy.contains(app.pid), !outOfTime() {
                var value: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(remembered, kAXTitleAttribute as CFString, &value)
                if status == .success {
                    accessibilityTitle = value as? String
                } else if status == .invalidUIElement {
                    element = nil
                }
            }
            let item = SwitcherItem(
                id: id,
                pid: app.pid,
                appName: app.name,
                bundleID: app.bundleID,
                title: OtherSpaceWindows.title(accessibility: accessibilityTitle, previous: previousTitles[id], windowServer: window.name),
                isMinimized: false,
                isAppHidden: app.isHidden,
                isFullscreen: candidate.isFullscreenSpace,
                isOnActiveSpace: false,
                displayID: described.frames[candidate.windowID].flatMap { display(for: $0, screens: screens) }
            )
            found.append(Found(item: item, element: element, order: otherSpacesOrder + min(rank, 49_999)))
        }
        return found
    }

    /// This process's window-server connection, or nil when other Spaces can't be listed.
    private static func otherSpacesConnection() -> Int32? {
        guard PrivateAPI.canListOtherSpaces, let id = PrivateAPI.cgsMainConnectionID?(), id != 0 else { return nil }
        return id
    }

    /// The windows on one Space, front to back.
    private static func windowIDs(onSpace space: UInt64, connection: Int32, copyWindows: PrivateAPI.CGSCopyWindowsWithOptionsAndTags) -> [UInt32] {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        let spaceList = [NSNumber(value: Int64(bitPattern: space))] as CFArray
        // +1 reference, released by takeRetainedValue.
        guard let list = copyWindows(connection, 0, spaceList, otherSpacesListOptions, &setTags, &clearTags)?.takeRetainedValue(),
              let numbers = list as? [NSNumber] else { return [] }
        return numbers.map(\.uint32Value).filter { $0 != 0 }
    }

    /// Public window-server descriptions (layer, alpha, bounds, owner, name) of `ids`.
    private static func describe(_ ids: [CGWindowID]) -> (windows: [UInt32: WindowServerWindow], frames: [UInt32: CGRect]) {
        var windows: [UInt32: WindowServerWindow] = [:]
        var frames: [UInt32: CGRect] = [:]
        // CGWindowListCreateDescriptionFromArray takes the IDs themselves as the array's
        // values (not CFNumbers), so the array has no callbacks: CF neither retains nor
        // releases them. `values` only has to live until CFArrayCreate has copied them.
        var values: [UnsafeRawPointer?] = ids.filter { $0 != 0 }.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard !values.isEmpty else { return (windows, frames) }
        let idArray: CFArray? = values.withUnsafeMutableBufferPointer { buffer in
            CFArrayCreate(kCFAllocatorDefault, buffer.baseAddress, buffer.count, nil)
        }
        guard let idArray,
              let list = CGWindowListCreateDescriptionFromArray(idArray) as? [[String: Any]] else { return (windows, frames) }
        for info in list {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            windows[number] = WindowServerWindow(
                id: number,
                pid: pid,
                layer: layer,
                alpha: alpha,
                width: Double(bounds.width),
                height: Double(bounds.height),
                name: info[kCGWindowName as String] as? String
            )
            frames[number] = bounds
        }
        return (windows, frames)
    }

    // MARK: - Helpers

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
