import AppKit
import SwiftUI
import TapTheTabCore

/// The small window behind the menu's "Check for Updates…" and "Update to …" items:
/// shows the check's result, so a check that finds nothing says so and a failed one
/// offers the release page.
@MainActor
final class UpdateWindowController: NSObject {
    private let updater: Updater
    private var window: NSWindow?

    init(updater: Updater) {
        self.updater = updater
        super.init()
    }

    /// Opens/raises the window and activates the app.
    func show() {
        let isNew = window == nil
        let window = self.window ?? makeWindow()
        self.window = window
        if isNew { window.center() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("Software Update")
        window.isReleasedWhenClosed = false
        // The hosting view's size follows the content (release notes appear and go).
        window.contentView = NSHostingView(rootView: UpdateWindowView(updater: updater))
        return window
    }
}

struct UpdateWindowView: View {
    @ObservedObject var updater: Updater

    private var appIcon: NSImage {
        let icon: NSImage? = NSApp.applicationIconImage
        return icon ?? NSImage()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("TapTheTab Updates"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                UpdateStatusView(updater: updater, showsScheduleNote: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
