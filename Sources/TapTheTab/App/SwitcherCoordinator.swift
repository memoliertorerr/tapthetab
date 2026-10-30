import AppKit
import TapTheTabCore

/// Drives one switcher session at a time: turns hotkey events into `SwitcherSession`
/// inputs and session effects into panel updates and window actions.
@MainActor
final class SwitcherCoordinator: NSObject, HotkeyMonitorDelegate {
    private let monitor = HotkeyMonitor()
    private let catalog = WindowCatalog()
    private let watcher = WindowWatcher()
    private let focus = FocusTracker()
    private let panel = SwitcherPanelController()
    private let thumbnails = ThumbnailService.make()
    private let peek = PeekController()
    private let permissions: PermissionsProviding

    private(set) var configuration: Configuration
    private(set) var isPaused = false
    /// How the last switch brought its window forward, for Copy Diagnostics.
    private(set) var lastSwitchMethod: String?
    /// The user dragged a block of the switcher: positions to remember (nil: default place).
    var onPositionsChanged: ((_ main: BlockPosition?, _ preview: BlockPosition?) -> Void)?
    /// ⇧P pinned or unpinned an app: the new list of pinned bundle IDs to save.
    var onPinnedAppsChanged: (([String]) -> Void)?
    private(set) var isStarted = false

    private var session: SwitcherSession?
    private var activeTrigger: Trigger?
    /// The appearance of the open session: the settings with the trigger's own style, if any.
    private var sessionAppearance = Appearance()
    private var router = KeyRouter(triggerKeyCode: KeyCode.tab)
    /// What was picked for which search, in memory only (never written to disk).
    private var searchMemory = SearchMemory()
    private var screen: NSScreen?
    private var sessionToken = 0
    private var showTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var lastThumbnailRequestIDs: [ItemID] = []
    private var outsideClickMonitor: Any?

    init(configuration: Configuration, permissions: PermissionsProviding) {
        self.configuration = configuration
        self.permissions = permissions
        super.init()
        panel.onInput = { [weak self] input in self?.handle(input) }
        panel.onPositionsChanged = { [weak self] main, preview in self?.onPositionsChanged?(main, preview) }
        configureCatalog()
    }

    // MARK: - Lifecycle

    /// Starts listening for shortcuts. Returns false when the event tap could not be created.
    @discardableResult
    func start() -> Bool {
        monitor.delegate = self
        monitor.triggers = configuration.triggers
        if !isStarted {
            focus.start()
            observeWorkspace()
            watcher.onChangeInApps = { [weak self] pids in self?.windowsChanged(in: pids) }
            watcher.start()
            catalog.refresh()
        }
        isStarted = true
        guard !isPaused else { return true }
        return monitor.start()
    }

    func stop() {
        close()
        monitor.stop()
        focus.stop()
        watcher.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        isStarted = false
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            close()
            monitor.stop()
        } else if isStarted {
            monitor.start()
        }
    }

    func apply(configuration newValue: Configuration) {
        let previewsTurnedOff = configuration.appearance.showPreviews && !newValue.appearance.showPreviews
        configuration = newValue
        monitor.triggers = newValue.triggers
        if previewsTurnedOff {
            thumbnails?.clear()
            panel.clearThumbnails()
        }
        close()
        let listedOtherSpaces = catalog.includesOtherSpaces
        configureCatalog()
        // Add or drop other Spaces' windows now, not at the next window change.
        if isStarted, catalog.includesOtherSpaces != listedOtherSpaces { windowsChanged(in: nil) }
    }

    /// Windows on other Spaces are listed only when shown and not filtered out anyway.
    private func configureCatalog() {
        catalog.includesOtherSpaces = configuration.filters.showOtherSpaces && !configuration.filters.currentSpaceOnly
    }

    /// Opens the switcher from the menu bar, locked open (no modifier to release).
    func openFromMenu() {
        guard session == nil, isStarted, !isPaused, monitor.isRunning else { return }
        let trigger = configuration.triggers.first { $0.scope == .allWindows } ?? configuration.triggers[0]
        monitor.beginSession()
        open(trigger: trigger, reverse: false, locked: true)
    }

    /// Opens the switcher for an automation request (`tapthetab://switch`), locked open
    /// and optionally pre-filtered. Ignored while a session is already open.
    func openFromAutomation(scope: SwitcherScope, query: String?) {
        guard session == nil, isStarted, !isPaused, monitor.isRunning else { return }
        let trigger = configuration.triggers.first { $0.scope == scope }
            ?? Trigger(shortcut: configuration.triggers[0].shortcut, scope: scope)
        monitor.beginSession()
        open(trigger: trigger, reverse: false, locked: true)
        if let query, !query.isEmpty, configuration.behavior.searchEnabled {
            handle(.type(query))
        }
    }

    /// Counts for the diagnostics report. No titles or app names.
    var diagnosticsCounts: (windows: Int, apps: Int, watchedApps: Int, fullRefreshMilliseconds: Int?, partialRefreshMilliseconds: Int?, skippedBySubrole: [String: Int]?) {
        let items = catalog.latest.items
        let windows = items.filter { !$0.isWindowless }.count
        let apps = Set(items.map(\.pid)).count
        return (windows, apps, watcher.watchedCount, lastFullRefreshMilliseconds, lastPartialRefreshMilliseconds, lastFullRefreshSkipped)
    }

    /// From the last full refresh, where every app was asked.
    private var lastFullRefreshSkipped: [String: Int]?

    private var lastFullRefreshMilliseconds: Int?
    private var lastPartialRefreshMilliseconds: Int?

    // MARK: - HotkeyMonitorDelegate

    func hotkeyMonitor(_ monitor: HotkeyMonitor, didTrigger trigger: Trigger, reverse: Bool) {
        // The tap may have matched just before a pause or config change stopped capture.
        guard monitor.isSessionActive, session == nil else { return }
        open(trigger: trigger, reverse: reverse, locked: !configuration.behavior.releaseToSwitch)
    }

    func hotkeyMonitor(_ monitor: HotkeyMonitor, keyDown press: KeyPress) {
        guard let current = session, let trigger = activeTrigger else { return }
        // If the modifier release itself was missed (the tap was briefly off), the next key
        // press shows the modifiers are up: treat it as the release.
        let required = trigger.shortcut.modifiers.intersection([.command, .option, .control])
        if !current.isLocked, !press.modifiers.isSuperset(of: required) {
            handle(.triggerReleased)
            return
        }
        // Another trigger's key (e.g. ⌥` during ⌥⇥) is not text.
        if press.keyCode != trigger.shortcut.keyCode,
           configuration.triggers.contains(where: { $0.shortcut.keyCode == press.keyCode && !$0.shortcut.modifiers.isEmpty && press.modifiers.isSuperset(of: $0.shortcut.modifiers.subtracting(.shift)) }) {
            return
        }
        guard let input = router.route(press, isSearching: current.isSearching) else { return }
        handle(input)
    }

    func hotkeyMonitor(_ monitor: HotkeyMonitor, modifiersChanged flags: ModifierFlags) {
        guard session != nil, let trigger = activeTrigger else { return }
        let required = trigger.shortcut.modifiers.intersection([.command, .option, .control])
        if !flags.isSuperset(of: required) { handle(.triggerReleased) }
    }

    /// Called when keyboard capture stopped working (Accessibility permission revoked).
    var onMonitorFailure: (() -> Void)?

    func hotkeyMonitorDidFail(_ monitor: HotkeyMonitor) {
        close()
        // Release the dead tap and hand ⌘⇥ back to the system until permission returns.
        monitor.stop()
        onMonitorFailure?()
    }

    /// Accessibility was revoked while we run: stop capture as if the tap had failed.
    func hotkeyMonitorDidFailFromPermissionChange() {
        guard monitor.isRunning else { return }
        hotkeyMonitorDidFail(monitor)
    }

    /// Settings is recording a shortcut: let existing triggers reach it.
    func setShortcutRecording(_ recording: Bool) {
        monitor.isMatchingSuspended = recording
    }

    // MARK: - Session

    private func open(trigger: Trigger, reverse: Bool, locked: Bool) {
        guard let screen = targetScreen() else {
            monitor.endSession()
            return
        }
        sessionToken += 1
        let token = sessionToken
        activeTrigger = trigger
        self.screen = screen
        router = KeyRouter(
            triggerKeyCode: trigger.shortcut.keyCode,
            searchEnabled: configuration.behavior.searchEnabled,
            triggerModifiers: trigger.shortcut.modifiers,
            quickSelectEnabled: configuration.behavior.quickSelect
        )
        sessionAppearance = configuration.appearance.effective(for: trigger)

        let items = buildItems(from: catalog.latest.items, scope: trigger.scope, screen: screen)
        var newSession = SwitcherSession(
            items: items,
            startsOnPrevious: configuration.behavior.startOnPrevious,
            locked: locked,
            columns: panel.columns(forItemCount: items.count, appearance: sessionAppearance, on: screen),
            wrapsAround: configuration.behavior.wrapAround,
            searchMemory: searchMemory
        )
        if reverse {
            newSession.handle(.last)
        } else if configuration.appearance.groupByApp, configuration.behavior.startOnPrevious,
                  let previous = previousWindowID(from: catalog.latest.items, scope: trigger.scope, screen: screen),
                  let index = newSession.visible.firstIndex(where: { $0.id == previous }) {
            // Grouping reorders the list, but a quick tap must still mean "the window I
            // used before this one", not "this app's other window".
            newSession.handle(.select(index: index))
        }
        session = newSession

        let delay = locked ? 0 : configuration.appearance.showDelayMilliseconds
        scheduleShow(afterMilliseconds: delay, token: token)
        // The watcher keeps the list current; re-ask only the frontmost app (its titles
        // matter most) unless the cache is old, in which case refresh everything.
        let stale = Date().timeIntervalSince(catalog.latest.date) > Self.fullRefreshAge
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let scope: Set<pid_t>? = (stale || front == nil) ? nil : [front!]
        catalog.refresh(onlyPIDs: scope) { [weak self] snapshot in
            self?.catalogDidRefresh(snapshot, token: token)
        }
    }

    /// Older than this, the cached window list is fully rebuilt when the switcher opens.
    private static let fullRefreshAge: TimeInterval = 30

    /// Pinned apps' bundle IDs, lowercased.
    private var pinnedSet: Set<String> {
        Set(configuration.filters.pinnedBundleIDs.map { $0.lowercased() })
    }

    private func close() {
        endPeek()
        showTask?.cancel()
        showTask = nil
        previewTask?.cancel()
        previewTask = nil
        sessionToken += 1
        session = nil
        activeTrigger = nil
        monitor.endSession()
        panel.hide()
        thumbnails?.cancelPending()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func handle(_ input: SwitcherInput) {
        guard var current = session else { return }
        // Any other key ends a peek first; ⇧Space toggles it.
        if input != .peek { endPeek() }
        let effect = current.handle(input)
        session = current

        switch effect {
        case .none:
            break
        case .refresh:
            if panel.isVisible {
                updatePanel()
                requestSelectedPreview()
            } else {
                // The user is interacting before the show delay ran out: show now.
                showTask?.cancel()
                showPanel()
            }
        case .activate(let item):
            if current.isSearching { searchMemory.record(query: current.query, picked: item) }
            let window = catalog.element(for: item.id) ?? lookUpWindow(item)
            close()
            lastSwitchMethod = WindowActions.activate(item, window: window, acrossSpaces: configuration.filters.showOtherSpaces)
            focus.touch(item.id)
        case .perform(let action, let item):
            perform(action, on: item)
        case .peek(let item):
            togglePeek(item)
        case .dismiss:
            close()
            returnFocusIfNeeded()
        }
    }

    private func perform(_ action: WindowAction, on item: SwitcherItem) {
        if action == .togglePin {
            togglePin(item)
            return
        }
        let ok = WindowActions.perform(action, on: item, window: catalog.element(for: item.id), acrossSpaces: configuration.filters.showOtherSpaces)
        guard ok, var current = session else {
            if !ok { NSSound.beep() }
            return
        }

        // Update optimistically so the panel reacts at once; a refresh follows.
        var items = current.items
        switch action {
        case .close:
            items.removeAll { $0.id == item.id }
        case .quitApp:
            items.removeAll { $0.pid == item.pid }
        case .minimize:
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isMinimized.toggle() }
        case .hideApp:
            let hidden = !item.isAppHidden
            for index in items.indices where items[index].pid == item.pid { items[index].isAppHidden = hidden }
        case .closeAppWindows:
            items.removeAll { $0.pid == item.pid && !$0.isWindowless }
        case .toggleFullscreen, .focus, .moveToNextDisplay, .togglePin:
            break
        }
        current.replaceItems(items)
        session = current
        if panel.isVisible { updatePanel() }

        let token = sessionToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.sessionToken == token else { return }
            self.catalog.refresh { [weak self] snapshot in
                self?.catalogDidRefresh(snapshot, token: token)
            }
        }
    }

    /// ⇧P: pin or unpin the item's app. Pinned apps' windows come first; the change is
    /// saved through `onPinnedAppsChanged` and the open list is re-ordered at once.
    private func togglePin(_ item: SwitcherItem) {
        guard let bundleID = item.bundleID?.trimmingCharacters(in: .whitespaces), !bundleID.isEmpty else {
            NSSound.beep()
            return
        }
        var pinned = configuration.filters.pinnedBundleIDs
        if let index = pinned.firstIndex(where: { $0.lowercased() == bundleID.lowercased() }) {
            pinned.remove(at: index)
        } else {
            pinned.append(bundleID)
        }
        configuration.filters.pinnedBundleIDs = pinned
        onPinnedAppsChanged?(pinned)
        guard var current = session else { return }
        let selected = current.selectedItem?.id
        current.replaceItems(ItemOrdering.pinnedFirst(current.items, pinnedBundleIDs: pinnedSet))
        if let selected, let index = current.visible.firstIndex(where: { $0.id == selected }) {
            current.handle(.select(index: index))
        }
        session = current
        if panel.isVisible {
            panel.setPinnedBundleIDs(pinnedSet)
            updatePanel()
        }
    }

    // MARK: - Peek

    /// ⇧Space: the selected window full size where it is, over a dimmed screen, or back.
    /// A still capture, so it needs Screen Recording; minimized windows have nothing to show.
    private func togglePeek(_ item: SwitcherItem) {
        if peek.isShowing {
            endPeek()
            return
        }
        guard permissions.screenRecordingGranted, let thumbnails, case .window(let number) = item.id,
              !item.isMinimized, !item.isAppHidden,
              let element = catalog.element(for: item.id) ?? lookUpWindow(item),
              let frame = AX.frame(element) else {
            NSSound.beep()
            return
        }
        let screen = NSScreen.screens.first { $0.topLeftFrame.intersects(frame) } ?? self.screen ?? NSScreen.main
        guard let screen else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let appKitFrame = NSRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let pixels = Int((max(frame.width, frame.height) * screen.backingScaleFactor).rounded(.up))
        let token = sessionToken
        thumbnails.capture(windowIDs: [number], maxPixelSize: pixels, storeInCache: false) { [weak self] _, image in
            guard let self, self.sessionToken == token, self.session?.selectedItem?.id == item.id else { return }
            self.peek.show(image: image, at: appKitFrame, on: screen)
        }
    }

    private func endPeek() {
        peek.hide()
    }

    private func catalogDidRefresh(_ snapshot: WindowCatalog.Snapshot, token: Int) {
        let milliseconds = Int((snapshot.duration * 1000).rounded())
        if snapshot.refreshedPIDs == nil {
            lastFullRefreshMilliseconds = milliseconds
            lastFullRefreshSkipped = snapshot.skippedBySubrole
        } else {
            lastPartialRefreshMilliseconds = milliseconds
        }
        focus.prune(after: snapshot.items)
        thumbnails?.prune(keeping: Set(snapshot.items.compactMap { item -> UInt32? in
            if case .window(let number) = item.id { return number }
            return nil
        }))
        guard token == sessionToken, var current = session, let trigger = activeTrigger, let screen else { return }
        current.replaceItems(buildItems(from: snapshot.items, scope: trigger.scope, screen: screen))
        current.columns = panel.columns(forItemCount: current.visible.count, appearance: sessionAppearance, on: screen)
        session = current
        if panel.isVisible {
            updatePanel()
            let ids = current.visible.map(\.id)
            if ids != lastThumbnailRequestIDs { requestThumbnails() }
        }
    }

    private func buildItems(from items: [SwitcherItem], scope: SwitcherScope, screen: NSScreen) -> [SwitcherItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let context = FilterContext(
            // Opened from a link, TapTheTab itself is frontmost; use the app before it.
            activePID: front == ownPID ? focus.lastActivePID : front,
            activeDisplayID: screen.displayID,
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
        let filtered = ItemFilter.apply(focus.ordered(items), options: configuration.filters, scope: scope, context: context)
        // Display first goes before grouping so each app's group stays whole.
        let sorted = ItemOrdering.displayFirst(
            filtered,
            displayID: configuration.filters.currentDisplayFirst ? screen.displayID : nil
        )
        let grouped = configuration.appearance.groupByApp ? ItemOrdering.groupedByApp(sorted) : sorted
        return ItemOrdering.pinnedFirst(grouped, pinnedBundleIDs: pinnedSet)
    }

    /// The second entry in plain recency order: what a quick tap should switch to.
    private func previousWindowID(from items: [SwitcherItem], scope: SwitcherScope, screen: NSScreen) -> ItemID? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let context = FilterContext(
            activePID: front == ownPID ? focus.lastActivePID : front,
            activeDisplayID: screen.displayID,
            ownPID: ownPID
        )
        let ordered = ItemFilter.apply(focus.ordered(items), options: configuration.filters, scope: scope, context: context)
        return ordered.count > 1 ? ordered[1].id : nil
    }

    // MARK: - Panel

    private func scheduleShow(afterMilliseconds delay: Int, token: Int) {
        showTask?.cancel()
        if delay <= 0 {
            showPanel()
            return
        }
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            guard !Task.isCancelled, let self, self.sessionToken == token else { return }
            self.showPanel()
        }
    }

    private func showPanel() {
        guard let current = session, let screen else { return }
        let columns = panel.show(
            session: current,
            appearance: sessionAppearance,
            behavior: configuration.behavior,
            on: screen,
            triggerModifiers: activeTrigger?.shortcut.modifiers ?? [],
            pinnedBundleIDs: pinnedSet
        )
        if columns != current.columns { session?.columns = columns }
        requestThumbnails()
        installOutsideClickMonitor()
    }

    private func updatePanel() {
        guard let current = session else { return }
        let columns = panel.update(session: current)
        if columns != current.columns { session?.columns = columns }
    }

    private func requestThumbnails() {
        guard configuration.appearance.showPreviews, let thumbnails, let current = session,
              permissions.screenRecordingGranted else { return }
        lastThumbnailRequestIDs = current.visible.map(\.id)
        var ids: [UInt32] = []
        for ranked in current.visible {
            guard case .window(let number) = ranked.id, !ranked.item.isMinimized, !ranked.item.isAppHidden else { continue }
            if let cached = thumbnails.cachedImage(for: number) { panel.setThumbnail(cached, for: ranked.id) }
            ids.append(number)
        }
        let longEdge = Int(configuration.appearance.size.cardSize.width * 2)
        thumbnails.capture(windowIDs: ids, maxPixelSize: longEdge) { [weak self] number, image in
            self?.panel.setThumbnail(image, for: .window(number))
        }
        requestSelectedPreview(after: 0)
    }

    /// The large preview needs a sharper image of the selected window than the cards do.
    /// Debounced so holding ⇥ doesn't start a capture per step.
    private func requestSelectedPreview(after delay: UInt64 = 80_000_000) {
        previewTask?.cancel()
        guard configuration.appearance.showPreviews, let thumbnails, permissions.screenRecordingGranted,
              let selected = session?.selectedItem, case .window(let number) = selected.id,
              !selected.isMinimized, !selected.isAppHidden,
              let size = panel.largePreviewMaxPixelSize,
              size > Int(configuration.appearance.size.cardSize.width * 2) else { return }
        let token = sessionToken
        previewTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled, let self, self.sessionToken == token,
                  self.session?.selectedItem?.id == selected.id else { return }
            thumbnails.capture(windowIDs: [number], maxPixelSize: size, storeInCache: false) { [weak self] number, image in
                self?.panel.setLargePreview(image, for: .window(number))
            }
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.close() }
        }
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        switch configuration.appearance.placement {
        case .mouse:
            let mouse = NSEvent.mouseLocation
            if let screen = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return screen }
        case .activeWindow:
            if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               let window = AX.element(AX.application(pid), kAXFocusedWindowAttribute),
               let frame = AX.frame(window) {
                let best = screens.max { a, b in
                    let ia = a.topLeftFrame.intersection(frame)
                    let ib = b.topLeftFrame.intersection(frame)
                    let areaA = ia.isNull ? 0 : ia.width * ia.height
                    let areaB = ib.isNull ? 0 : ib.width * ib.height
                    return areaA < areaB
                }
                if let best { return best }
            }
        case .main:
            if let first = screens.first { return first }
        }
        return NSScreen.main ?? screens.first
    }

    // MARK: - Keeping the window list warm

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        // A session can't end by key release while the screen is locked or the Mac sleeps.
        center.addObserver(self, selector: #selector(systemWillSleepOrLock(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemWillSleepOrLock(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(systemWillSleepOrLock(_:)), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
    }

    /// A selected window the cached snapshot has no element for (the app was busy during
    /// the last refresh): ask the app directly before falling back to reopening it.
    private func lookUpWindow(_ item: SwitcherItem) -> AXUIElement? {
        guard case .window(let number) = item.id else { return nil }
        return AX.elements(AX.application(item.pid), kAXWindowsAttribute).first { AX.windowID($0) == number }
    }

    /// After a link opened the switcher TapTheTab is the active app; dismissing must not
    /// leave the keyboard focus on an app with no windows.
    private func returnFocusIfNeeded() {
        guard NSApp.isActive, let pid = focus.lastActivePID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [])
    }

    @objc private func systemWillSleepOrLock(_ note: Notification) {
        close()
    }

    @objc private func workspaceChanged(_ note: Notification) {
        // Apps launched, quit, hid or the Space changed: everything may have moved.
        windowsChanged(in: nil)
    }

    /// Windows changed in `pids` (nil: possibly anywhere): refresh the cache, and the open
    /// switcher too (a window closed elsewhere disappears from the panel).
    private func windowsChanged(in pids: Set<pid_t>?) {
        let token = sessionToken
        catalog.refresh(onlyPIDs: pids) { [weak self] snapshot in
            self?.catalogDidRefresh(snapshot, token: token)
        }
    }
}
