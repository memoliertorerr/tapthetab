import AppKit
import SwiftUI
import TapTheTabCore

/// A panel that never takes keyboard focus; keys reach the switcher through the event tap.
final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a click on an inactive, non-key panel act immediately instead of being swallowed.
final class SwitcherHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The switcher's two blocks, each in its own window so either can be dragged.
enum SwitcherBlock {
    /// Search bar plus grid or list.
    case main
    /// The large preview's card.
    case preview
}

@MainActor
final class SwitcherPanelController {
    /// Mouse interaction: hover sends .select(index:) (only when behavior.mouseHoverSelects),
    /// click sends .select(index:) then .commit. Index is into session.visible.
    var onInput: ((SwitcherInput) -> Void)?
    /// A block was dragged: the positions to remember (nil: the default place).
    var onPositionsChanged: ((_ main: BlockPosition?, _ preview: BlockPosition?) -> Void)?

    var isVisible: Bool { mainPanel.isVisible }

    private let model: SwitcherViewModel
    private let mainPanel: SwitcherPanel
    private let previewPanel: SwitcherPanel
    private let mainHost: SwitcherHostingView<SwitcherMainView>
    private let previewHost: SwitcherHostingView<SwitcherPreviewView>
    /// A shadow refresh of the preview window is queued for after SwiftUI drew the change.
    private var shadowRefreshPending = false
    private var screen: NSScreen?
    /// Where the blocks are for the current showing: the remembered positions, or the
    /// main block's default place fixed when the panel opened, so resizes keep its top
    /// edge (the search bar does not jump while typing). A nil preview position means the
    /// card follows the main block.
    private var mainPosition: BlockPosition?
    private var previewPosition: BlockPosition?
    /// The main block is at a remembered (dragged) position rather than its default place.
    private var mainWasMoved = false
    /// The drag in progress: which block, and where the pointer and the windows started.
    private var drag: (block: SwitcherBlock, mouse: NSPoint, main: NSPoint, preview: NSPoint)?

    init() {
        let model = SwitcherViewModel()
        let mainHost = SwitcherHostingView(rootView: SwitcherMainView(model: model))
        let previewHost = SwitcherHostingView(rootView: SwitcherPreviewView(model: model))
        mainHost.sizingOptions = []
        previewHost.sizingOptions = []
        self.model = model
        self.mainHost = mainHost
        self.previewHost = previewHost
        mainPanel = SwitcherPanelController.makePanel(content: mainHost)
        previewPanel = SwitcherPanelController.makePanel(content: previewHost)

        model.inputHandler = { [weak self] input in
            self?.onInput?(input)
        }
        model.dragHandler = { [weak self] block, phase in
            self?.handleDrag(block, phase)
        }
    }

    /// A transparent, borderless, non-activating panel; the SwiftUI content draws its
    /// backdrop (glass or blur) and the window shadow follows that shape.
    private static func makePanel(content: NSView) -> SwitcherPanel {
        let rect = NSRect(origin: .zero, size: SwitcherLayout.minimumSize)
        let panel = SwitcherPanel(
            contentRect: rect,
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
        content.frame = rect
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        return panel
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

    /// Shows (or re-shows) the blocks on `screen`: where the user last dragged them, or
    /// centred. Returns the column count used.
    @discardableResult
    func show(session: SwitcherSession, appearance: Appearance, behavior: Behavior, on screen: NSScreen) -> Int {
        self.screen = screen
        drag = nil
        let nsAppearance = Self.nsAppearance(for: appearance.theme)
        mainPanel.appearance = nsAppearance
        previewPanel.appearance = nsAppearance

        let layout = Self.layout(
            for: session,
            appearance: appearance,
            showsPreview: previewAvailable(for: session, appearance: appearance),
            screenSize: screen.visibleFrame.size
        )
        model.present(session: session, appearance: appearance, behavior: behavior, layout: layout)
        mainPosition = appearance.panelPosition
        previewPosition = appearance.previewPosition
        mainWasMoved = appearance.panelPosition != nil
        let frames = placement(for: layout, in: screen)
        if mainPosition == nil {
            // Keep the default place's top edge for the rest of this showing.
            mainPosition = PanelPlacement.mainPosition(of: ScreenRect(frames.main), in: ScreenRect(screen.visibleFrame))
        }
        apply(frames)
        renderNow()
        if frames.preview != nil { previewPanel.orderFrontRegardless() }
        mainPanel.orderFrontRegardless()
        return layout.columns
    }

    /// Re-renders with a new session state (selection, query, items). Resizes if needed,
    /// keeping the blocks' places from `show`. Returns columns.
    @discardableResult
    func update(session: SwitcherSession) -> Int {
        let layout = currentLayout(for: session)
        let previewCardBefore = model.previewCardSize
        model.update(session: session, layout: layout)
        relayout()
        if model.previewCardSize != previewCardBefore { refreshShadowSoon() }
        return layout.columns
    }

    /// Window preview arrived (or nil to clear). Ignored when previews are off.
    /// When it is the selected item's, the large preview appears (or goes) at once.
    func setThumbnail(_ image: CGImage?, for id: ItemID) {
        let previewCardBefore = model.previewCardSize
        model.setThumbnail(image, for: id)
        if id == model.session.selectedItem?.id { relayoutForPreview(previewCardBefore: previewCardBefore) }
    }

    /// A sharper image of a window for the large preview; only the latest is kept.
    func setLargePreview(_ image: CGImage?, for id: ItemID) {
        let previewCardBefore = model.previewCardSize
        model.setLargePreview(image, for: id)
        if id == model.session.selectedItem?.id { relayoutForPreview(previewCardBefore: previewCardBefore) }
    }

    /// Drop all cached thumbnails (e.g. when previews get turned off).
    func clearThumbnails() {
        let previewCardBefore = model.previewCardSize
        model.clearThumbnails()
        relayoutForPreview(previewCardBefore: previewCardBefore)
    }

    /// Size in pixels of the box the large preview of the selected window gets in the
    /// current session (points × the screen's backing scale factor), or nil when the large
    /// preview is off or does not fit. Available before the selected window's thumbnail
    /// exists, so its capture can be sized for the box. The image is aspect-fit inside,
    /// so a capture whose long edge is `max(width, height)` is always sharp enough.
    var largePreviewPixelSize: CGSize? {
        guard model.appearance.showPreviews, model.appearance.showLargePreview,
              model.session.selectedItem != nil else { return nil }
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
        drag = nil
        model.isDragging = false
        mainPanel.orderOut(nil)
        previewPanel.orderOut(nil)
    }

    // MARK: - Layout

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
            previewScale: appearance.largePreviewScale,
            sectionHeaderCount: SwitcherViewModel.sectionHeaderIndices(for: session, appearance: appearance).count,
            listThumbnails: appearance.showPreviews && appearance.windowThumbnails
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

    /// The preview box is reserved whenever the large preview is on and something is
    /// selected, even before (or without) a thumbnail, so the blocks don't jump while
    /// arrowing past minimized or hidden windows; those show their app icon instead.
    private func previewAvailable(for session: SwitcherSession, appearance: Appearance) -> Bool {
        appearance.showPreviews && appearance.showLargePreview && session.selectedItem != nil
    }

    /// Re-lays out the shown session after the selected item's thumbnail came or went.
    /// The preview card can change shape without its window changing size (another
    /// window's proportions), so its shadow is refreshed whenever the card changed.
    private func relayoutForPreview(previewCardBefore: CGSize) {
        guard isVisible else { return }
        let session = model.session
        let layout = currentLayout(for: session)
        if layout != model.layout {
            model.update(session: session, layout: layout)
            relayout()
        }
        if model.previewCardSize != previewCardBefore { refreshShadowSoon() }
    }

    /// Frames for `layout` at the current positions on `screen`.
    private func placement(for layout: SwitcherLayout, in screen: NSScreen) -> (main: NSRect, preview: NSRect?) {
        let frames = PanelPlacement.frames(
            visible: ScreenRect(screen.visibleFrame),
            mainSize: Size(layout.mainSize),
            previewSize: layout.showsPreview ? Size(layout.previewCardSize) : nil,
            mainPosition: mainPosition,
            previewPosition: previewPosition
        )
        return (NSRect(frames.main), frames.preview.map { NSRect($0) })
    }

    /// Moves and resizes the visible blocks to the current layout and positions. Not while
    /// a block is being dragged: the pointer owns its place then.
    private func relayout() {
        guard isVisible, drag == nil, let screen else { return }
        let frames = placement(for: model.layout, in: screen)
        let moved = mainPanel.frame != frames.main
            || (frames.preview.map { $0 != previewPanel.frame || !previewPanel.isVisible } ?? false)
        apply(frames)
        guard moved else { return }
        renderNow()
        // Cards moved under a resting pointer must not count as hover.
        model.resetHoverBaseline()
        if frames.preview != nil, !previewPanel.isVisible {
            previewPanel.orderFrontRegardless()
            mainPanel.orderFrontRegardless()
        }
    }

    private func apply(_ frames: (main: NSRect, preview: NSRect?)) {
        if mainPanel.frame != frames.main {
            mainPanel.setFrame(frames.main, display: true, animate: false)
        }
        if let preview = frames.preview {
            if previewPanel.frame != preview {
                previewPanel.setFrame(preview, display: true, animate: false)
            }
        } else if previewPanel.isVisible {
            previewPanel.orderOut(nil)
        }
    }

    // MARK: - Dragging

    /// A block is dragged with the mouse while the switcher is open. It stays on the
    /// screen; a card that follows the main block moves with it. When the drag ends the
    /// new positions are reported so they can be remembered.
    private func handleDrag(_ block: SwitcherBlock, _ phase: SwitcherDragPhase) {
        guard let screen, isVisible else { return }
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .changed:
            if drag == nil {
                drag = (block, mouse, mainPanel.frame.origin, previewPanel.frame.origin)
                model.isDragging = true
            }
            guard let drag, drag.block == block else { return }
            let delta = NSPoint(x: mouse.x - drag.mouse.x, y: mouse.y - drag.mouse.y)
            let visible = ScreenRect(screen.visibleFrame)
            switch block {
            case .main:
                let moved = PanelPlacement.clamp(ScreenRect(NSRect(origin: drag.main.offset(by: delta), size: mainPanel.frame.size)), in: visible)
                mainPanel.setFrameOrigin(NSPoint(x: moved.x, y: moved.y))
                if previewPosition == nil, previewPanel.isVisible {
                    // The card follows the main block: it keeps its place relative to it.
                    let shift = NSPoint(x: moved.x - drag.main.x, y: moved.y - drag.main.y)
                    let card = PanelPlacement.clamp(ScreenRect(NSRect(origin: drag.preview.offset(by: shift), size: previewPanel.frame.size)), in: visible)
                    previewPanel.setFrameOrigin(NSPoint(x: card.x, y: card.y))
                }
            case .preview:
                let moved = PanelPlacement.clamp(ScreenRect(NSRect(origin: drag.preview.offset(by: delta), size: previewPanel.frame.size)), in: visible)
                previewPanel.setFrameOrigin(NSPoint(x: moved.x, y: moved.y))
            }
        case .ended:
            guard let drag, drag.block == block else { return }
            self.drag = nil
            model.isDragging = false
            model.resetHoverBaseline()
            let visible = ScreenRect(screen.visibleFrame)
            switch block {
            case .main:
                guard mainPanel.frame.origin != drag.main else { return }
                mainPosition = PanelPlacement.mainPosition(of: ScreenRect(mainPanel.frame), in: visible)
                mainWasMoved = true
            case .preview:
                guard previewPanel.frame.origin != drag.preview else { return }
                previewPosition = PanelPlacement.previewPosition(of: ScreenRect(previewPanel.frame), in: visible)
            }
            onPositionsChanged?(mainWasMoved ? mainPosition : nil, previewPosition)
        }
    }

    // MARK: - Drawing

    /// Recomputes the preview window's shadow from the drawn content once SwiftUI has
    /// rendered the current state (the shadow follows the card, which hugs the image).
    private func refreshShadowSoon() {
        guard !shadowRefreshPending else { return }
        shadowRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.shadowRefreshPending = false
            guard self.previewPanel.isVisible else { return }
            self.previewHost.layoutSubtreeIfNeeded()
            self.previewPanel.displayIfNeeded()
            self.previewPanel.invalidateShadow()
        }
    }

    /// Pushes pending SwiftUI changes through before the blocks become visible, so they
    /// never flash the previous session's content, then fits the shadows to what was drawn.
    private func renderNow() {
        mainHost.layoutSubtreeIfNeeded()
        mainPanel.displayIfNeeded()
        mainPanel.invalidateShadow()
        if model.layout.showsPreview {
            previewHost.layoutSubtreeIfNeeded()
            previewPanel.displayIfNeeded()
            previewPanel.invalidateShadow()
        }
    }

    private static func nsAppearance(for theme: Theme) -> NSAppearance? {
        switch theme {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

extension ScreenRect {
    init(_ rect: NSRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y), width: Double(rect.width), height: Double(rect.height))
    }
}

extension NSRect {
    init(_ rect: ScreenRect) {
        self.init(x: CGFloat(rect.x), y: CGFloat(rect.y), width: CGFloat(rect.width), height: CGFloat(rect.height))
    }
}

private extension NSPoint {
    func offset(by delta: NSPoint) -> NSPoint {
        NSPoint(x: x + delta.x, y: y + delta.y)
    }
}
