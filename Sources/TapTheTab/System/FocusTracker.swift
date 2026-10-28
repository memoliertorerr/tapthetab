import AppKit
import ApplicationServices
import TapTheTabCore

/// Keeps a most-recently-used order of windows by watching app activation and,
/// inside the frontmost app, focused-window changes. Main-thread only.
final class FocusTracker {
    private(set) var recency = RecencyTracker()
    /// The most recent app other than TapTheTab that was frontmost.
    private(set) var lastActivePID: pid_t?
    /// Which process each seen item belongs to, so pruning can keep the history of
    /// windows that are only temporarily missing (busy app, other Space).
    private var owners: [ItemID: pid_t] = [:]
    private var observeRetries: [pid_t: Int] = [:]
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var workspaceTokens: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.appActivated(app)
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.appTerminated(app.processIdentifier)
        })
        if let front = NSWorkspace.shared.frontmostApplication { appActivated(front) }
    }

    func stop() {
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        removeObserver()
    }

    func touch(_ id: ItemID) { recency.touch(id) }

    func ordered(_ items: [SwitcherItem]) -> [SwitcherItem] { recency.ordered(items) }

    /// Forgets history only for items whose app is no longer running. Items missing from
    /// one snapshot (an app too busy to answer, a window on another Space) keep their place.
    func prune(after snapshot: [SwitcherItem]) {
        for item in snapshot { owners[item.id] = item.pid }
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        owners = owners.filter { running.contains($0.value) }
        recency.prune(keeping: Set(owners.keys))
    }

    // MARK: - Private

    private func appActivated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lastActivePID = pid
        recordFocusedWindow(of: pid)
        observe(pid: pid)
    }

    private func appTerminated(_ pid: pid_t) {
        recency.forget(.app(pid: pid))
        if lastActivePID == pid { lastActivePID = nil }
        observeRetries[pid] = nil
        if observedPID == pid { removeObserver() }
    }

    fileprivate func recordFocusedWindow(of pid: pid_t) {
        let app = AX.application(pid)
        if let window = AX.element(app, kAXFocusedWindowAttribute), let id = AX.windowID(window) {
            recency.touch(.window(id))
        } else {
            recency.touch(.app(pid: pid))
        }
    }

    private func observe(pid: pid_t) {
        guard observedPID != pid else { return }
        removeObserver()
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            // AX observers fire on the run loop they were added to: the main one.
            if let pid = tracker.observedPID { tracker.recordFocusedWindow(of: pid) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
        let app = AX.application(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let focused = AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        let main = AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
        guard focused == .success || main == .success else {
            // A freshly launched app often isn't ready for AX yet; try again shortly.
            let attempt = (observeRetries[pid] ?? 0) + 1
            observeRetries[pid] = attempt
            if attempt <= 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(attempt)) { [weak self] in
                    guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    self.observe(pid: pid)
                }
            }
            return
        }
        observeRetries[pid] = nil
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        self.observedPID = pid
    }

    private func removeObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = nil
    }
}
