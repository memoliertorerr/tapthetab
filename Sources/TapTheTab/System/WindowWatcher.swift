import AppKit
import ApplicationServices

/// Tells the catalog when any app's windows change, so the window list is already
/// current when the switcher opens. One AXObserver per regular app; events are
/// coalesced into a single `onChange` call. Main-thread only.
final class WindowWatcher {
    /// Called on the main thread, at most once per `debounceInterval`.
    var onChange: (() -> Void)?

    private let debounceInterval: TimeInterval = 0.12
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var retries: [pid_t: Int] = [:]

    /// Notifications registered on each app element. Most apps deliver them for every
    /// window of the app when registered on the application element.
    private static let appNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
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

    fileprivate func scheduleChange() {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.onChange?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
