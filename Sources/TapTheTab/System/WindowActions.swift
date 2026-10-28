import AppKit
import ApplicationServices
import TapTheTabCore

/// Focus, close, minimize and friends, using only public APIs.
enum WindowActions {
    /// Brings a window (or a windowless app) to the front, un-hiding and
    /// un-minimizing as needed.
    static func activate(_ item: SwitcherItem, window: AXUIElement?) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }

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
    static func perform(_ action: WindowAction, on item: SwitcherItem, window: AXUIElement?) -> Bool {
        let app = NSRunningApplication(processIdentifier: item.pid)
        switch action {
        case .focus:
            activate(item, window: window)
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

    private static func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate(options: [])
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
