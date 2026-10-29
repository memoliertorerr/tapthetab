import AppKit

/// "Peek" (⇧Space in the switcher): the selected window shown full size where it is,
/// over a dimmed screen. It is a still image from
/// ScreenCaptureKit (the window itself is not touched or raised), so it needs the
/// Screen Recording permission. It covers the switcher; clicks go through; ⇧Space or
/// any other key ends it.
@MainActor
final class PeekController {
    private var panel: NSPanel?
    private var imageView: NSImageView?

    private(set) var isShowing = false

    /// Shows `image` at `frame` (AppKit screen coordinates) on `screen`.
    func show(image: CGImage, at frame: NSRect, on screen: NSScreen) {
        let panel = self.panel ?? makePanel()
        let imageView = self.imageView ?? makeImageView(in: panel)
        panel.setFrame(screen.frame, display: false)
        imageView.image = NSImage(cgImage: image, size: frame.size)
        // The image view is placed in the panel's coordinates (origin at the screen's corner).
        imageView.frame = NSRect(
            x: frame.minX - screen.frame.minX,
            y: frame.minY - screen.frame.minY,
            width: frame.width,
            height: frame.height
        )
        panel.orderFrontRegardless()
        isShowing = true
    }

    func hide() {
        guard isShowing else { return }
        panel?.orderOut(nil)
        imageView?.image = nil
        isShowing = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        // Above the switcher's panels, which stay where they are underneath.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        self.panel = panel
        return panel
    }

    private func makeImageView(in panel: NSPanel) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.setAccessibilityElement(false)
        panel.contentView?.addSubview(view)
        imageView = view
        return view
    }
}
