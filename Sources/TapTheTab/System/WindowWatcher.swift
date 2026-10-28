import AppKit
import ApplicationServices

/// Tells the catalog when any app's windows change, so the window list is already
/// current when the switcher opens. One AXObserver per regular app; events are
/// coalesced into a single `onChange` call. Main-thread only.
final class WindowWatcher {
    /// Called on the main thread once events have been quiet for `debounceInterval`.
    var onChange: (() -> Void)?

    private let debounceInterval: TimeInterval = 0.25
    /// Upper bound on how long a steady stream of events can postpone a refresh.
    private let maximumDelay: TimeInterval = 1.0
    private var firstPendingEvent: Date?
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var retries: [pid_t: Int] = [:]

    /// Notifications registered on each app element. Title and destroyed events are not
    /// here: on the app element they fire for every tab, cell and tooltip in the app, which
    /// would re-enumerate all windows constantly. They are registered per window instead.
    private static let appNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXFocusedWindowChangedNotification,
    ]

    /// Registered on each new window as well, for apps that only report these per window.
    private static let windowNotifications: [String] = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
    ]

    deinit { stop() }

    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // A freshly launched app often isn't ready for AX yet.
            let pid = app.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.watch(pid) }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.unwatch(app.processIdentifier)
        })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            watch(app.processIdentifier)
        }
    }

    func stop() {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens.removeAll()
        for pid in Array(observers.keys) { unwatch(pid) }
        pending?.cancel()
        pending = nil
        firstPendingEvent = nil
    }

    var watchedCount: Int { observers.count }

    // MARK: - Private

    private func watch(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.activationPolicy == .regular else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            if (notification as String) == kAXWindowCreatedNotification {
                watcher.register(window: element, on: observer)
            }
            watcher.scheduleChange()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }

        let element = AX.application(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = 0
        for name in Self.appNotifications {
            let result = AXObserverAddNotification(observer, element, name as CFString, refcon)
            if result == .success || result == .notificationAlreadyRegistered { registered += 1 }
        }
        guard registered > 0 else {
            // Not ready yet (or not an AX-capable app): try again a couple of times.
            let attempt = (retries[pid] ?? 0) + 1
            retries[pid] = attempt
            if attempt <= 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt)) { [weak self] in self?.watch(pid) }
            }
            return
        }
        retries[pid] = nil
        for window in AX.elements(element, kAXWindowsAttribute) {
            register(window: window, on: observer)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func unwatch(_ pid: pid_t) {
        retries[pid] = nil
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        scheduleChange()
    }

    fileprivate func register(window: AXUIElement, on observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }

    /// Trailing debounce: refresh once things go quiet, but never later than `maximumDelay`
    /// after the first event, so a constantly retitling window still gets picked up.
    fileprivate func scheduleChange() {
        let now = Date()
        let first = firstPendingEvent ?? now
        firstPendingEvent = first
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.firstPendingEvent = nil
            self.onChange?()
        }
        pending = work
        let delay = min(debounceInterval, max(0, maximumDelay - now.timeIntervalSince(first)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
