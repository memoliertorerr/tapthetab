import AppKit
import ApplicationServices
import TapTheTabCore

/// Focus, close, minimize and friends. Public APIs only, except focusing a window on
/// another Space (see `focusAcrossSpaces`), which only happens when windows on other
/// Spaces are shown.
enum WindowActions {
    /// Brings a window (or a windowless app) to the front, un-hiding and
    /// un-minimizing as needed.
    ///
    /// `acrossSpaces` is true while "Show windows on other Spaces" is on: a window that is
    /// not on the current Space (or has no Accessibility element) is then made frontmost
    /// through the window server, which also switches to its Space. Without it, or when
    /// that fails, the public path below runs as before.
    static func activate(_ item: SwitcherItem, window: AXUIElement?, acrossSpaces: Bool = false) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }

        if acrossSpaces, case .window(let number) = item.id,
           !item.isOnActiveSpace || window == nil,
           // Minimized windows and hidden apps' windows are off-screen on every Space;
           // the public path below restores those.
           !item.isMinimized, !item.isAppHidden,
           focusAcrossSpaces(pid: item.pid, windowID: number) {
            if let window {
                AX.set(window, kAXMainAttribute, true)
                AX.perform(window, kAXRaiseAction)
            }
            activateApp(app)
            if let window {
                // The Space switch is animated; raise once more when it has settled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    AX.perform(window, kAXRaiseAction)
                    AX.set(window, kAXMainAttribute, true)
                }
            }
            return
        }

        if item.isWindowless || window == nil {
            // Re-opening through Launch Services sends the "reopen" event, which makes
            // most apps create a window, just like clicking the Dock icon.
            if let url = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
            } else {
                activateApp(app)
            }
            return
        }

        if app.isHidden { app.unhide() }
        guard let window else { return }
        if AX.bool(window, kAXMinimizedAttribute) == true {
            AX.set(window, kAXMinimizedAttribute, false)
        }
        AX.set(window, kAXMainAttribute, true)
        AX.perform(window, kAXRaiseAction)
        AX.set(AX.application(item.pid), kAXFrontmostAttribute, true)
        activateApp(app)
        // Activation can reorder the app's windows (and Space switches are animated);
        // raising once more afterwards keeps the chosen window on top.
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

    // MARK: - Other Spaces (private window-server calls)

    /// `_SLPSSetFrontProcessWithOptions` mode: act as if the user chose the window, so
    /// the window server switches to its Space.
    private static let userGeneratedFrontProcess: UInt32 = 0x200

    /// Makes `windowID` the key window of the frontmost process `pid`, switching to its
    /// Space. Returns false (having changed nothing that matters) when a private function
    /// is missing or the window server refuses, so the caller can use the public path.
    /// Main thread.
    private static func focusAcrossSpaces(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let getProcess = PrivateAPI.getProcessForPID,
              let setFront = PrivateAPI.slpsSetFrontProcessWithOptions,
              let post = PrivateAPI.slpsPostEventRecordTo,
              windowID != 0 else { return false }
        // `psn` and `record` are locals passed by pointer for the duration of each
        // synchronous call only; nothing keeps the pointers afterwards.
        var psn = ProcessSerialNumber()
        guard getProcess(pid, &psn) == 0 else { return false }  // 0 is noErr
        guard setFront(&psn, windowID, userGeneratedFrontProcess) == .success else { return false }
        var record = keyWindowEventRecord(windowID: windowID)
        record.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            // Phase 1 then phase 2 of the same "make key" record (offset 0x08).
            base[0x08] = 0x01
            _ = post(&psn, base)
            base[0x08] = 0x02
            _ = post(&psn, base)
        }
        return true
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
