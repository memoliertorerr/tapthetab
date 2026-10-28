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
    private let permissions: PermissionsProviding

    private(set) var configuration: Configuration
    private(set) var isPaused = false
    private(set) var isStarted = false

    private var session: SwitcherSession?
    private var activeTrigger: Trigger?
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
            watcher.onChange = { [weak self] in self?.windowsChanged() }
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
    var diagnosticsCounts: (windows: Int, apps: Int, watchedApps: Int) {
        let items = catalog.latest.items
        let windows = items.filter { !$0.isWindowless }.count
        let apps = Set(items.map(\.pid)).count
        return (windows, apps, watcher.watchedCount)
    }

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
        router = KeyRouter(triggerKeyCode: trigger.shortcut.keyCode, searchEnabled: configuration.behavior.searchEnabled, triggerModifiers: trigger.shortcut.modifiers)

        let items = buildItems(from: catalog.latest.items, scope: trigger.scope, screen: screen)
        var newSession = SwitcherSession(
            items: items,
            startsOnPrevious: configuration.behavior.startOnPrevious,
            locked: locked,
            columns: panel.columns(forItemCount: items.count, appearance: configuration.appearance, on: screen),
            wrapsAround: configuration.behavior.wrapAround,
            searchMemory: searchMemory
        )
        if reverse { newSession.handle(.last) }
        session = newSession

        let delay = locked ? 0 : configuration.appearance.showDelayMilliseconds
        scheduleShow(afterMilliseconds: delay, token: token)
        catalog.refresh { [weak self] snapshot in
            self?.catalogDidRefresh(snapshot, token: token)
        }
    }

    private func close() {
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
            WindowActions.activate(item, window: window)
            focus.touch(item.id)
        case .perform(let action, let item):
            perform(action, on: item)
        case .dismiss:
            close()
            returnFocusIfNeeded()
        }
    }

    private func perform(_ action: WindowAction, on item: SwitcherItem) {
        let ok = WindowActions.perform(action, on: item, window: catalog.element(for: item.id))
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
        case .toggleFullscreen, .focus:
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

    private func catalogDidRefresh(_ snapshot: WindowCatalog.Snapshot, token: Int) {
        focus.prune(after: snapshot.items)
        thumbnails?.prune(keeping: Set(snapshot.items.compactMap { item -> UInt32? in
            if case .window(let number) = item.id { return number }
            return nil
        }))
        guard token == sessionToken, var current = session, let trigger = activeTrigger, let screen else { return }
        current.replaceItems(buildItems(from: snapshot.items, scope: trigger.scope, screen: screen))
        current.columns = panel.columns(forItemCount: current.visible.count, appearance: configuration.appearance, on: screen)
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
        return ItemFilter.apply(focus.ordered(items), options: configuration.filters, scope: scope, context: context)
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
        let columns = panel.show(session: current, appearance: configuration.appearance, behavior: configuration.behavior, on: screen)
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
            thumbnails.capture(windowIDs: [number], maxPixelSize: size) { [weak self] number, image in
                self?.panel.setThumbnail(image, for: .window(number))
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
        windowsChanged()
    }

    /// Something about the set of windows changed: refresh the cache, and the open
    /// switcher too (a window closed elsewhere disappears from the panel).
    private func windowsChanged() {
        let token = sessionToken
        catalog.refresh { [weak self] snapshot in
            self?.catalogDidRefresh(snapshot, token: token)
        }
    }
}
