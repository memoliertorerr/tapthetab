import AppKit
import ApplicationServices
import TapTheTabCore

/// Focus, close, minimize and friends. Focusing a window goes through the window server
/// (see `focusWindow`) so only the chosen window comes forward; the public path is the
/// fallback when those private functions are missing.
enum WindowActions {
    /// Brings a window (or a windowless app) to the front, un-hiding and
    /// un-minimizing as needed. Only the chosen window comes forward: the app's other
    /// windows stay where they are in the stack, like clicking a window does.
    ///
    /// `acrossSpaces` is true while "Show windows on other Spaces" is on: a window on
    /// another Space (or without an Accessibility element) is then focused through the
    /// window server too, which also switches to its Space.
    ///
    /// Returns how the window was brought forward, for Copy Diagnostics (fixed wording,
    /// never window or app names).
    @discardableResult
    static func activate(_ item: SwitcherItem, window: AXUIElement?, acrossSpaces: Bool = false) -> String {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return "app not running" }

        if acrossSpaces, case .window(let number) = item.id,
           !item.isOnActiveSpace || window == nil,
           // Minimized windows and hidden apps' windows are off-screen on every Space;
           // the path below restores those first.
           !item.isMinimized, !item.isAppHidden,
           let method = focusWindow(pid: item.pid, windowID: number) {
            if let window {
                AX.perform(window, kAXRaiseAction)
                AX.set(window, kAXMainAttribute, true)
                raiseAgainSoon(window)
            }
            return method + ", other Space"
        }

        if item.isWindowless || window == nil {
            // Re-opening through Launch Services sends the "reopen" event, which makes
            // most apps create a window, just like clicking the Dock icon.
            if let url = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
                return "reopened app"
            }
            activateApp(app)
            return "activated app"
        }

        if app.isHidden { app.unhide() }
        guard let window else { return "no window" }
        if AX.bool(window, kAXMinimizedAttribute) == true {
            AX.set(window, kAXMinimizedAttribute, false)
        }
        // The window server makes the app frontmost with just this window, as a click on
        // it would, then the window is raised within its app. Making the app frontmost
        // any other way (its Accessibility "frontmost" attribute, or activating it)
        // brings all of its windows forward.
        if case .window(let number) = item.id, let method = focusWindow(pid: item.pid, windowID: number) {
            AX.perform(window, kAXRaiseAction)
            AX.set(window, kAXMainAttribute, true)
            raiseAgainSoon(window)
            return method
        }
        // Fallback when the window-server functions are missing: activate the app (its key
        // window only), and only if that is refused, its "frontmost" attribute, which can
        // bring all of its windows forward.
        AX.set(window, kAXMainAttribute, true)
        AX.perform(window, kAXRaiseAction)
        activateApp(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !app.isActive {
                Log.windows.notice("Activation refused; using the frontmost attribute")
                AX.set(AX.application(item.pid), kAXFrontmostAttribute, true)
            }
            AX.perform(window, kAXRaiseAction)
            AX.set(window, kAXMainAttribute, true)
        }
        return PrivateAPI.canFocusAcrossSpaces ? "public fallback, window server refused" : "public fallback, window server unavailable"
    }

    /// Activation can reorder the app's windows (and Space switches are animated);
    /// raising once more afterwards keeps the chosen window on top.
    private static func raiseAgainSoon(_ window: AXUIElement) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AX.perform(window, kAXRaiseAction)
            AX.set(window, kAXMainAttribute, true)
        }
    }

    /// Runs a non-focus action. Returns false when the app refused it.
    @discardableResult
    static func perform(_ action: WindowAction, on item: SwitcherItem, window: AXUIElement?, acrossSpaces: Bool = false) -> Bool {
        let app = NSRunningApplication(processIdentifier: item.pid)
        switch action {
        case .focus:
            activate(item, window: window, acrossSpaces: acrossSpaces)
            return true
        case .close:
            guard let window, let button = AX.element(window, kAXCloseButtonAttribute) else { return false }
            return AX.perform(button, kAXPressAction)
        case .minimize:
            guard let window else { return false }
            let minimized = AX.bool(window, kAXMinimizedAttribute) ?? false
            return AX.set(window, kAXMinimizedAttribute, !minimized)
        case .toggleFullscreen:
            guard let window else { return false }
            let fullscreen = AX.bool(window, AX.fullScreenAttribute) ?? false
            return AX.set(window, AX.fullScreenAttribute, !fullscreen)
        case .hideApp:
            guard let app else { return false }
            return app.isHidden ? app.unhide() : app.hide()
        case .quitApp:
            return app?.terminate() ?? false
        }
    }

    // MARK: - Window-server focus (private calls)

    /// `_SLPSSetFrontProcessWithOptions` mode: act as if the user chose the window, so
    /// the window server switches to its Space if needed. Without the "all windows" flag
    /// (0x100), only that window comes forward.
    private static let userGeneratedFrontProcess: UInt32 = 0x200

    /// Makes process `pid` frontmost with `windowID` as its key window, bringing only that
    /// window forward and switching to its Space if needed. Returns false (having changed
    /// nothing that matters) when a private function is missing or the window server
    /// refuses, so the caller can use the public path. Otherwise returns a description of
    /// what was done, for Copy Diagnostics. Main thread.
    private static func focusWindow(pid: pid_t, windowID: CGWindowID) -> String? {
        guard let getProcess = PrivateAPI.getProcessForPID,
              let setFront = PrivateAPI.slpsSetFrontProcessWithOptions,
              let post = PrivateAPI.slpsPostEventRecordTo,
              windowID != 0 else { return nil }
        // `psn` and `record` are locals passed by pointer for the duration of each
        // synchronous call only; nothing keeps the pointers afterwards.
        var psn = ProcessSerialNumber()
        guard getProcess(pid, &psn) == 0 else { return nil }  // 0 is noErr
        // The status is only reported: the call can do its job and still return non-zero,
        // and falling back afterwards would bring every window of the app forward again
        // (other window managers ignore it too).
        let status = setFront(&psn, windowID, userGeneratedFrontProcess)
        var record = keyWindowEventRecord(windowID: windowID)
        record.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            // Phase 1 then phase 2 of the same "make key" record (offset 0x08).
            base[0x08] = 0x01
            _ = post(&psn, base)
            base[0x08] = 0x02
            _ = post(&psn, base)
        }
        return "window server, status \(status.rawValue)"
    }

    /// The raw event record that tells a process which of its windows becomes key.
    ///
    /// The layout is not documented; it is what the window server is known to accept
    /// (a fact about the system, as used by several open-source window managers):
    /// - the buffer is 0x100 bytes, all zero except the fields below. A 0xf8-byte buffer
    ///   makes `SLPSPostEventRecordTo` abort on macOS 14, so the larger size matters;
    /// - 0x04: 0xf8, the record length field;
    /// - 0x08: the phase, set by the caller to 0x01 and then 0x02 for the two posts;
    /// - 0x20 to 0x2f: 0xff;
    /// - 0x3a: 0x10, the record type;
    /// - 0x3c to 0x3f: the window ID, 32-bit little-endian (the window server's byte order).
    private static func keyWindowEventRecord(windowID: CGWindowID) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xf8
        for offset in 0x20..<0x30 { record[offset] = 0xff }
        record[0x3a] = 0x10
        // Shifting the value (not its in-memory bytes) gives little-endian on any host.
        record[0x3c] = UInt8(truncatingIfNeeded: windowID)
        record[0x3d] = UInt8(truncatingIfNeeded: windowID >> 8)
        record[0x3e] = UInt8(truncatingIfNeeded: windowID >> 16)
        record[0x3f] = UInt8(truncatingIfNeeded: windowID >> 24)
        return record
    }

    private static func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate(options: [])
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
