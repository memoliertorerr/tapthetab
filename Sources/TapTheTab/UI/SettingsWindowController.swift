import AppKit
import SwiftUI
import TapTheTabCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsViewModel
    private var window: NSWindow?
    private var statusTimer: Timer?
    private var hasBeenCentered = false

    init(
        configuration: Configuration,
        permissions: PermissionsProviding,
        launchAtLogin: LaunchAtLoginProviding,
        configFileURL: URL,
        onChange: @escaping (Configuration) -> Void
    ) {
        self.model = SettingsViewModel(
            configuration: configuration,
            permissions: permissions,
            launchAtLogin: launchAtLogin,
            configFileURL: configFileURL,
            onChange: onChange
        )
        super.init()
    }

    /// Opens/raises the window and activates the app.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.refreshStatus()
        if !hasBeenCentered {
            window.center()
            hasBeenCentered = true
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startStatusTimer()
    }

    /// The configuration changed from outside (e.g. file edited); refresh the UI without calling onChange.
    func update(configuration: Configuration) {
        model.applyExternal(configuration)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
        stopStatusTimer()
    }

    /// A shortcut recording only makes sense while this window gets the keys.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    // MARK: - Private

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("TapTheTab Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 640, height: 520))
        return window
    }

    private func startStatusTimer() {
        guard statusTimer == nil else { return }
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(statusTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        statusTimer = timer
    }

    private func stopStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    @objc private func statusTimerFired(_ timer: Timer) {
        model.refreshStatus()
    }
}
