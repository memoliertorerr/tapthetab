import AppKit
import SwiftUI
import TapTheTabCore

/// The window closes on ⎋ like a dialog.
private final class TourWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// The short first-run tour (and "Show Tour…" later). One window at a time; showing it
/// again starts from the first page.
@MainActor
final class TourWindowController: NSObject, NSWindowDelegate {
    /// UserDefaults key: set once the tour has been shown (or skipped).
    static let shownDefaultsKey = "tourShown"
    static let shared = TourWindowController()

    private var window: NSWindow?

    /// Whether the tour was shown before.
    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: shownDefaultsKey)
    }

    /// Shows the tour unless it was shown before. Returns whether it opened.
    /// Call it once Accessibility has been granted for the first time.
    @discardableResult
    static func showIfFirstRun(modifier: String = "⌥", theme: ColorTheme = .none) -> Bool {
        guard !hasBeenShown else { return false }
        show(modifier: modifier, theme: theme)
        return true
    }

    /// Opens the tour at its first page ("Show Tour…").
    /// - Parameters:
    ///   - modifier: the trigger's modifier symbol (⌥ ⌘ ⌃ ⇧), so the examples match the shortcut.
    ///   - theme: the switcher's color theme, for a matching look.
    static func show(modifier: String = "⌥", theme: ColorTheme = .none) {
        shared.present(modifier: modifier, theme: theme)
    }

    // MARK: - Private

    private func present(modifier: String, theme: ColorTheme) {
        UserDefaults.standard.set(true, forKey: Self.shownDefaultsKey)
        window?.close()

        let model = TourViewModel(modifier: modifier, theme: theme)
        model.onFinish = { [weak self] in
            self?.window?.close()
        }
        let window = TourWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("TapTheTab Tour")
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hostingView = NSHostingView(rootView: TourView(model: model))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 560, height: 470))
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
    }
}
