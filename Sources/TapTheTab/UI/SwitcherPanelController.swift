import AppKit
import SwiftUI
import TapTheTabCore

/// A panel that never takes keyboard focus; keys reach the switcher through the event tap.
final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a click on an inactive, non-key panel act immediately instead of being swallowed.
final class SwitcherHostingView: NSHostingView<SwitcherRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SwitcherPanelController {
    /// Mouse interaction: hover sends .select(index:) (only when behavior.mouseHoverSelects),
    /// click sends .select(index:) then .commit. Index is into session.visible.
    var onInput: ((SwitcherInput) -> Void)?

    var isVisible: Bool { panel.isVisible }

    private static let cornerRadius: CGFloat = 18

    private let model: SwitcherViewModel
    private let panel: SwitcherPanel
    private let effectView: NSVisualEffectView
    private let hostingView: SwitcherHostingView
    private var screen: NSScreen?

    init() {
        let model = SwitcherViewModel()
        let initialRect = NSRect(origin: .zero, size: SwitcherLayout.minimumSize)

        let panel = SwitcherPanel(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        let effectView = NSVisualEffectView(frame: initialRect)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Self.cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]

        let hostingView = SwitcherHostingView(rootView: SwitcherRootView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)
        panel.contentView = effectView

        self.model = model
        self.panel = panel
        self.effectView = effectView
        self.hostingView = hostingView

        model.inputHandler = { [weak self] input in
            self?.onInput?(input)
        }
    }

    /// How many columns a layout would use for this many items on that screen
    /// (always 1 for the list style).
    func columns(forItemCount count: Int, appearance: Appearance, on screen: NSScreen) -> Int {
        let layout = SwitcherLayout.compute(
            style: appearance.style,
            size: appearance.size,
            itemCount: count,
            showsSearchBar: appearance.style == .list,
            screenSize: screen.visibleFrame.size
        )
        return layout.columns
    }

    /// Shows (or re-shows) the panel centred on `screen`'s visibleFrame. Returns the column count used.
    @discardableResult
    func show(session: SwitcherSession, appearance: Appearance, behavior: Behavior, on screen: NSScreen) -> Int {
        self.screen = screen
        panel.appearance = Self.nsAppearance(for: appearance.theme)

        let layout = Self.layout(for: session, appearance: appearance, screenSize: screen.visibleFrame.size)
        model.present(session: session, appearance: appearance, behavior: behavior, layout: layout)
        applyFrame(size: layout.panelSize, on: screen)
        renderNow()
        panel.orderFrontRegardless()
        return layout.columns
    }

    /// Re-renders with a new session state (selection, query, items). Resizes/recentres if needed. Returns columns.
    @discardableResult
    func update(session: SwitcherSession) -> Int {
        let screenSize: CGSize = (screen ?? NSScreen.main)?.visibleFrame.size ?? SwitcherLayout.fallbackScreenSize
        let layout = Self.layout(for: session, appearance: model.appearance, screenSize: screenSize)
        model.update(session: session, layout: layout)

        if panel.isVisible, let screen {
            let current = panel.frame.size
            if current.width != layout.panelSize.width || current.height != layout.panelSize.height {
                applyFrame(size: layout.panelSize, on: screen)
                renderNow()
                // Cards moved under a resting pointer must not count as hover.
                model.resetHoverBaseline()
            }
        }
        return layout.columns
    }

    /// Window preview arrived (or nil to clear). Ignored when previews are off.
    func setThumbnail(_ image: CGImage?, for id: ItemID) {
        model.setThumbnail(image, for: id)
    }

    /// Drop all cached thumbnails (e.g. when previews get turned off).
    func clearThumbnails() {
        model.clearThumbnails()
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - Private

    private static func layout(for session: SwitcherSession, appearance: Appearance, screenSize: CGSize) -> SwitcherLayout {
        let showsSearch = appearance.style == .list || session.isSearching || session.isLocked
        return SwitcherLayout.compute(
            style: appearance.style,
            size: appearance.size,
            itemCount: session.visible.count,
            showsSearchBar: showsSearch,
            screenSize: screenSize
        )
    }

    private func applyFrame(size: CGSize, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let origin = NSPoint(
            x: (visible.midX - width / 2).rounded(),
            y: (visible.midY - height / 2).rounded()
        )
        let frame = NSRect(origin: origin, size: NSSize(width: width, height: height))
        if frame != panel.frame {
            panel.setFrame(frame, display: true, animate: false)
            panel.invalidateShadow()
        }
    }

    /// Pushes pending SwiftUI changes through before the panel becomes visible,
    /// so it never flashes the previous session's content.
    private func renderNow() {
        hostingView.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    private static func nsAppearance(for theme: Theme) -> NSAppearance? {
        switch theme {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Stretchable rounded-rect mask for the visual effect view.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
