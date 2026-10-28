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
    /// Top edge and horizontal centre of the panel for the current showing. Later
    /// resizes keep these fixed, so the search bar does not jump while typing.
    private var anchor: (top: CGFloat, midX: CGFloat)?

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

        let layout = Self.layout(
            for: session,
            appearance: appearance,
            showsPreview: previewAvailable(for: session, appearance: appearance),
            screenSize: screen.visibleFrame.size
        )
        model.present(session: session, appearance: appearance, behavior: behavior, layout: layout)
        let frame = Self.centredFrame(size: layout.panelSize, in: screen.visibleFrame)
        anchor = (top: frame.maxY, midX: frame.midX)
        applyFrame(frame)
        renderNow()
        panel.orderFrontRegardless()
        return layout.columns
    }

    /// Re-renders with a new session state (selection, query, items). Resizes if needed,
    /// keeping the top edge and horizontal centre from `show`. Returns columns.
    @discardableResult
    func update(session: SwitcherSession) -> Int {
        let layout = currentLayout(for: session)
        model.update(session: session, layout: layout)
        resizeIfNeeded(to: layout)
        return layout.columns
    }

    /// Window preview arrived (or nil to clear). Ignored when previews are off.
    /// When it is the selected item's, the large preview appears (or goes) at once.
    func setThumbnail(_ image: CGImage?, for id: ItemID) {
        model.setThumbnail(image, for: id)
        if id == model.session.selectedItem?.id { relayoutForPreview() }
    }

    /// A sharper image of a window for the large preview; only the latest is kept.
    func setLargePreview(_ image: CGImage?, for id: ItemID) {
        model.setLargePreview(image, for: id)
        if id == model.session.selectedItem?.id { relayoutForPreview() }
    }

    /// Drop all cached thumbnails (e.g. when previews get turned off).
    func clearThumbnails() {
        model.clearThumbnails()
        relayoutForPreview()
    }

    /// Size in pixels of the box the large preview of the selected window gets in the
    /// current session (points × the screen's backing scale factor), or nil when previews
    /// are off or no preview fits. Available before the selected window's thumbnail
    /// exists, so its capture can be sized for the box. The image is aspect-fit inside,
    /// so a capture whose long edge is `max(width, height)` is always sharp enough.
    var largePreviewPixelSize: CGSize? {
        guard model.appearance.showPreviews, model.session.selectedItem != nil else { return nil }
        let target: NSScreen? = screen ?? NSScreen.main
        let screenSize: CGSize = target?.visibleFrame.size ?? SwitcherLayout.fallbackScreenSize
        let layout = Self.layout(for: model.session, appearance: model.appearance, showsPreview: true, screenSize: screenSize)
        guard layout.showsPreview else { return nil }
        let scale: CGFloat = target?.backingScaleFactor ?? 2
        return CGSize(
            width: (layout.previewSize.width * scale).rounded(.up),
            height: (layout.previewSize.height * scale).rounded(.up)
        )
    }

    /// A capture long edge (pixels) that is sharp in the large preview for any portrait
    /// window and any landscape window up to 16:9 (wider ones are only slightly soft), or
    /// nil when no preview fits. Usually far below the box width, which is wide when the
    /// grid is.
    var largePreviewMaxPixelSize: Int? {
        guard let box = largePreviewPixelSize else { return nil }
        let longEdge = max(box.height, min(box.width, box.height * 16 / 9))
        return Int(longEdge.rounded(.up))
    }

    func hide() {
        anchor = nil
        panel.orderOut(nil)
    }

    // MARK: - Private

    /// Also used by `ScreenshotRenderer`, so the screenshots are sized like the real panel.
    static func layout(
        for session: SwitcherSession,
        appearance: Appearance,
        showsPreview: Bool,
        screenSize: CGSize
    ) -> SwitcherLayout {
        let showsSearch = appearance.style == .list || session.isSearching || session.isLocked
        return SwitcherLayout.compute(
            style: appearance.style,
            size: appearance.size,
            itemCount: session.visible.count,
            showsSearchBar: showsSearch,
            screenSize: screenSize,
            showsPreview: showsPreview,
            sectionHeaderCount: SwitcherViewModel.sectionHeaderIndices(for: session, appearance: appearance).count
        )
    }

    /// Layout for `session` with the current appearance on the current screen.
    private func currentLayout(for session: SwitcherSession) -> SwitcherLayout {
        let screenSize: CGSize = (screen ?? NSScreen.main)?.visibleFrame.size ?? SwitcherLayout.fallbackScreenSize
        return Self.layout(
            for: session,
            appearance: model.appearance,
            showsPreview: previewAvailable(for: session, appearance: model.appearance),
            screenSize: screenSize
        )
    }

    /// The large preview is shown only in previews mode and once the selected item has a thumbnail.
    /// The preview box is reserved whenever previews are on and something is selected,
    /// even before (or without) a thumbnail, so the cards don't jump while arrowing past
    /// minimized or hidden windows; those show their app icon in the box instead.
    private func previewAvailable(for session: SwitcherSession, appearance: Appearance) -> Bool {
        appearance.showPreviews && session.selectedItem != nil
    }

    /// Re-lays out the shown session after the selected item's thumbnail came or went.
    private func relayoutForPreview() {
        guard panel.isVisible else { return }
        let session = model.session
        let layout = currentLayout(for: session)
        guard layout != model.layout else { return }
        model.update(session: session, layout: layout)
        resizeIfNeeded(to: layout)
    }

    /// Resizes a visible panel to `layout`, keeping the top edge and horizontal centre from `show`.
    private func resizeIfNeeded(to layout: SwitcherLayout) {
        guard panel.isVisible, let screen else { return }
        let current = panel.frame.size
        guard current.width != layout.panelSize.width || current.height != layout.panelSize.height else { return }
        let visible = screen.visibleFrame
        let frame: NSRect
        if let anchor {
            frame = Self.anchoredFrame(size: layout.panelSize, top: anchor.top, midX: anchor.midX, in: visible)
        } else {
            frame = Self.centredFrame(size: layout.panelSize, in: visible)
        }
        applyFrame(frame)
        renderNow()
        // Cards moved under a resting pointer must not count as hover.
        model.resetHoverBaseline()
    }

    /// Centred in `visible`, at most as large as it.
    private static func centredFrame(size: CGSize, in visible: NSRect) -> NSRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let origin = NSPoint(
            x: (visible.midX - width / 2).rounded(),
            y: (visible.midY - height / 2).rounded()
        )
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    /// Top edge at `top` and centred on `midX`, shifted as little as needed to stay inside `visible`.
    private static func anchoredFrame(size: CGSize, top: CGFloat, midX: CGFloat, in visible: NSRect) -> NSRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        var x = (midX - width / 2).rounded()
        x = min(max(x, visible.minX), visible.maxX - width)
        var y = (top - height).rounded()
        y = min(max(y, visible.minY), visible.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func applyFrame(_ frame: NSRect) {
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
