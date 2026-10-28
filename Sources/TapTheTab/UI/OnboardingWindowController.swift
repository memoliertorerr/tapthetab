import AppKit
import SwiftUI
import TapTheTabCore

/// Live permission state for the onboarding window.
@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var screenRecordingGranted: Bool

    var onDone: (() -> Void)?
    private let permissions: PermissionsProviding

    init(permissions: PermissionsProviding) {
        self.permissions = permissions
        self.accessibilityGranted = permissions.accessibilityGranted
        self.screenRecordingGranted = permissions.screenRecordingGranted
    }

    func refresh() {
        let accessibility = permissions.accessibilityGranted
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        let screenRecording = permissions.screenRecordingGranted
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }
    }

    func requestAccessibility() {
        permissions.requestAccessibility()
        refresh()
    }

    func requestScreenRecording() {
        permissions.requestScreenRecording()
        refresh()
    }

    func done() {
        onDone?()
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: OnboardingViewModel
    private let onFinish: () -> Void
    private var window: NSWindow?
    private var statusTimer: Timer?
    private var hasBeenCentered = false

    init(permissions: PermissionsProviding, onFinish: @escaping () -> Void) {
        self.model = OnboardingViewModel(permissions: permissions)
        self.onFinish = onFinish
        super.init()
        model.onDone = { [weak self] in
            self?.finish()
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        if !hasBeenCentered {
            window.center()
            hasBeenCentered = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startStatusTimer()
    }

    func close() {
        stopStatusTimer()
        if let window, window.isVisible {
            window.close()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopStatusTimer()
    }

    // MARK: - Private

    private func finish() {
        close()
        onFinish()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("Welcome to TapTheTab")
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hostingView = NSHostingView(rootView: OnboardingView(model: model))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 520, height: 420))
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
        model.refresh()
    }
}
