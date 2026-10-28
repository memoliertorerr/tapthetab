import AppKit
import ApplicationServices
import TapTheTabCore

/// Keeps a most-recently-used order of windows by watching app activation and,
/// inside the frontmost app, focused-window changes. Main-thread only.
final class FocusTracker {
    private(set) var recency = RecencyTracker()
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

    func prune(keeping ids: Set<ItemID>) { recency.prune(keeping: ids) }

    // MARK: - Private

    private func appActivated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        recordFocusedWindow(of: pid)
        observe(pid: pid)
    }

    private func appTerminated(_ pid: pid_t) {
        recency.forget(.app(pid: pid))
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
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
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
