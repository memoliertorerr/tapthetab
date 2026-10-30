import AppKit
import SwiftUI
import TapTheTabCore
import UniformTypeIdentifiers

/// State behind the switcher panel. Owned by `SwitcherPanelController`.
@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published private(set) var session: SwitcherSession = SwitcherSession(items: [])
    @Published private(set) var appearance: Appearance = Appearance()
    @Published private(set) var behavior: Behavior = Behavior()
    @Published private(set) var layout: SwitcherLayout = SwitcherLayout.initial
    @Published private(set) var thumbnails: [ItemID: CGImage] = [:]
    /// The sharper image for the large preview. Only one is kept: the selected window's.
    @Published private(set) var largePreview: (id: ItemID, image: CGImage)?
    /// Bumped on every show so scroll views start fresh.
    @Published private(set) var generation: Int = 0
    /// Modifiers of the shortcut that opened the switcher; quick-select labels depend on them.
    @Published private(set) var triggerModifiers: ModifierFlags = []
    /// Lowercased bundle IDs of pinned apps, for the pin badge.
    @Published private(set) var pinnedBundleIDs: Set<String> = []
    /// Scale of both blocks while they appear (below 1 only during the entrance).
    @Published private(set) var entranceScale: CGFloat = 1

    var inputHandler: ((SwitcherInput) -> Void)?
    /// True while a block is dragged: hover must not change the selection then.
    var isDragging = false {
        didSet { if oldValue && !isDragging { dragEndedAt = ProcessInfo.processInfo.systemUptime } }
    }
    /// When the last drag ended: the click that finishes a drag must not switch.
    private var dragEndedAt: TimeInterval = 0
    private static let clickAfterDragSuppression: TimeInterval = 0.3
    /// Icons to show instead of the running process's, by pid. Always empty in the app;
    /// `ScreenshotRenderer` sets it because its sample items have no real processes.
    var iconOverrides: [Int32: NSImage] = [:]

    private var iconCache: [Int32: NSImage] = [:]
    /// Mouse position when hover last counted (or when the panel appeared / relaid out).
    /// Hover only selects once the mouse has really moved, so a panel appearing under a
    /// resting pointer does not steal the selection.
    private var hoverBaseline: NSPoint?
    /// `systemUptime` of the last update that moved the selection without the mouse.
    /// Hover is ignored shortly after, so typing or arrowing is not undone by a card
    /// sliding under the pointer.
    private var lastKeyboardSelectionChange: TimeInterval = 0
    /// True while a hover or click is being forwarded, so the resulting update does not
    /// count as keyboard navigation.
    private var isForwardingPointerInput = false
    private static let hoverSuppression: TimeInterval = 0.15

    private lazy var genericAppIcon: NSImage = NSWorkspace.shared.icon(for: UTType.application)

    /// How the selection highlight and the preview card move between windows.
    static let selectionAnimation: Animation = .spring(response: 0.24, dampingFraction: 0.86)
    /// How long the selection animation takes to settle, for refreshing window shadows after it.
    static let selectionAnimationDuration: TimeInterval = 0.3
    /// The fade and scale of the blocks appearing.
    static let entranceDuration: TimeInterval = 0.12
    static let entranceStartScale: CGFloat = 0.97

    /// Animations are on in the appearance and Reduce Motion is off.
    var animates: Bool {
        appearance.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func present(
        session: SwitcherSession,
        appearance: Appearance,
        behavior: Behavior,
        layout: SwitcherLayout,
        triggerModifiers: ModifierFlags = [],
        pinnedBundleIDs: Set<String> = []
    ) {
        // A new showing never animates from the previous one's state.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            apply(session: session, appearance: appearance, behavior: behavior, layout: layout,
                  triggerModifiers: triggerModifiers, pinnedBundleIDs: pinnedBundleIDs)
        }
    }

    private func apply(
        session: SwitcherSession,
        appearance: Appearance,
        behavior: Behavior,
        layout: SwitcherLayout,
        triggerModifiers: ModifierFlags,
        pinnedBundleIDs: Set<String>
    ) {
        let ids = Set(session.items.map { $0.id })
        let pids = Set(session.items.map { $0.pid })
        iconCache = iconCache.filter { pids.contains($0.key) }
        if appearance.showPreviews {
            let kept = thumbnails.filter { ids.contains($0.key) }
            if kept.count != thumbnails.count { thumbnails = kept }
        } else if !thumbnails.isEmpty {
            thumbnails = [:]
        }

        if self.appearance != appearance { self.appearance = appearance }
        if self.behavior != behavior { self.behavior = behavior }
        if self.layout != layout { self.layout = layout }
        if self.triggerModifiers != triggerModifiers { self.triggerModifiers = triggerModifiers }
        setPinnedBundleIDs(pinnedBundleIDs)
        self.session = session
        generation += 1
        resetHoverBaseline()
    }

    /// Only the selection moved (same items, query and layout): that change slides the
    /// highlight and reshapes the preview card when animations are on. Anything else is
    /// applied at once.
    func update(session: SwitcherSession, layout: SwitcherLayout) {
        let selectionMoved = Self.selectionChanged(from: self.session, to: session)
        if !isForwardingPointerInput, selectionMoved {
            lastKeyboardSelectionChange = ProcessInfo.processInfo.systemUptime
        }
        if selectionMoved, animates, self.layout == layout, Self.sameContent(self.session, session) {
            withAnimation(Self.selectionAnimation) {
                self.session = session
            }
            return
        }
        if self.layout != layout { self.layout = layout }
        if self.session != session { self.session = session }
    }

    /// Prepares the blocks for appearing: slightly smaller when they will animate in,
    /// full size otherwise. Applied without animation, before the first frame is drawn.
    func prepareEntrance(animated: Bool) {
        let scale: CGFloat = animated ? Self.entranceStartScale : 1
        guard entranceScale != scale else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            entranceScale = scale
        }
    }

    /// Grows the blocks to full size (after `prepareEntrance(animated: true)`).
    func playEntrance() {
        guard entranceScale != 1 else { return }
        withAnimation(.easeOut(duration: Self.entranceDuration)) {
            entranceScale = 1
        }
    }

    /// The selected window's image changing reshapes the preview card, so it animates
    /// like a selection change; other windows' images just appear.
    func setThumbnail(_ image: CGImage?, for id: ItemID) {
        guard appearance.showPreviews else { return }
        animatingIfSelected(id) {
            if let image {
                thumbnails[id] = image
            } else if thumbnails[id] != nil {
                thumbnails.removeValue(forKey: id)
            }
        }
    }

    func clearThumbnails() {
        if !thumbnails.isEmpty { thumbnails = [:] }
        if largePreview != nil { largePreview = nil }
    }

    func setLargePreview(_ image: CGImage?, for id: ItemID) {
        guard appearance.showPreviews else { return }
        animatingIfSelected(id) {
            if let image {
                largePreview = (id, image)
            } else if largePreview?.id == id {
                largePreview = nil
            }
        }
    }

    private func animatingIfSelected(_ id: ItemID, _ change: () -> Void) {
        if animates, layout.showsPreview, session.selectedItem?.id == id {
            withAnimation(Self.selectionAnimation, change)
        } else {
            change()
        }
    }

    /// The label for picking the item at `index` (in `session.visible`) directly, e.g. "⌘1";
    /// nil when quick select is off or for items past the ninth.
    func quickSelectLabel(forIndex index: Int) -> String? {
        guard behavior.quickSelect else { return nil }
        return QuickSelect.label(forIndex: index, triggerModifiers: triggerModifiers)
    }

    /// Stored lowercased; compared with the items' bundle IDs ignoring case.
    func setPinnedBundleIDs(_ bundleIDs: Set<String>) {
        let pinned = Set(bundleIDs.map { $0.lowercased() })
        if pinnedBundleIDs != pinned { pinnedBundleIDs = pinned }
    }

    /// The item's app is pinned (its windows come first).
    func isPinned(_ item: SwitcherItem) -> Bool {
        guard !pinnedBundleIDs.isEmpty, let bundleID = item.bundleID else { return false }
        return pinnedBundleIDs.contains(bundleID.lowercased())
    }

    func thumbnail(for id: ItemID) -> CGImage? {
        guard appearance.showPreviews else { return nil }
        return thumbnails[id]
    }

    /// The thumbnail a card or list row shows, or nil for the app icon alone.
    func itemThumbnail(for id: ItemID) -> CGImage? {
        guard appearance.windowThumbnails else { return nil }
        return thumbnail(for: id)
    }

    /// List rows show window thumbnails (taller rows, see `PanelLayout`).
    var listShowsThumbnails: Bool {
        appearance.showPreviews && appearance.windowThumbnails
    }

    /// Whether a thumbnail is stored for `id`, whatever the current appearance says
    /// (the panel controller checks `showPreviews` against the appearance being shown).
    func hasThumbnail(for id: ItemID) -> Bool {
        thumbnails[id] != nil
    }

    /// Positions in `session.visible` that get an app-name heading above them (list style
    /// grouped by app, not searching). The layout reserves their height.
    var sectionHeaders: Set<Int> {
        Set(Self.sectionHeaderIndices(for: session, appearance: appearance))
    }

    nonisolated static func sectionHeaderIndices(for session: SwitcherSession, appearance: Appearance) -> [Int] {
        // Skips copying the items on every render when grouping is off (the common case).
        guard appearance.groupByApp else { return [] }
        return ItemOrdering.sectionHeaderIndices(
            for: session.visible.map(\.item),
            groupByApp: appearance.groupByApp,
            style: appearance.style,
            isSearching: session.isSearching
        )
    }

    /// The large preview's image: the selected item's thumbnail, when the layout has room for it.
    var selectedPreview: CGImage? {
        guard layout.showsPreview, let id = session.selectedItem?.id else { return nil }
        if let large = largePreview, large.id == id, appearance.showPreviews { return large.image }
        return thumbnail(for: id)
    }

    /// Size of the preview card as currently drawn: hugging the selected window's image,
    /// the whole box while there is none, `.zero` without a preview.
    var previewCardSize: CGSize {
        guard layout.showsPreview, session.selectedItem != nil else { return .zero }
        guard let image = selectedPreview else { return layout.previewCardSize }
        return layout.previewCardSize(fitting: CGSize(width: image.width, height: image.height))
    }

    /// Cached per process; not published, so filling the cache during rendering is fine.
    func icon(for pid: Int32) -> NSImage {
        if let override = iconOverrides[pid] { return override }
        if let cached = iconCache[pid] { return cached }
        let image: NSImage = NSRunningApplication(processIdentifier: pid)?.icon ?? genericAppIcon
        iconCache[pid] = image
        return image
    }

    func resetHoverBaseline() {
        hoverBaseline = NSEvent.mouseLocation
    }

    func hover(index: Int, inside: Bool) {
        guard inside, behavior.mouseHoverSelects, !isDragging else { return }
        let location: NSPoint = NSEvent.mouseLocation
        if let baseline = hoverBaseline, baseline == location { return }
        let now: TimeInterval = ProcessInfo.processInfo.systemUptime
        if now - lastKeyboardSelectionChange < Self.hoverSuppression { return }
        hoverBaseline = location
        guard index != session.selectedIndex else { return }
        forwardPointerInput(.select(index: index))
    }

    func click(index: Int) {
        guard !isDragging,
              ProcessInfo.processInfo.systemUptime - dragEndedAt > Self.clickAfterDragSuppression else { return }
        forwardPointerInput(.select(index: index))
        forwardPointerInput(.commit)
    }

    private func forwardPointerInput(_ input: SwitcherInput) {
        isForwardingPointerInput = true
        defer { isForwardingPointerInput = false }
        inputHandler?(input)
    }

    /// Same visible items in the same order and the same query.
    private static func sameContent(_ old: SwitcherSession, _ new: SwitcherSession) -> Bool {
        guard old.query == new.query, old.visible.count == new.visible.count else { return false }
        return old.visible.map(\.id) == new.visible.map(\.id)
    }

    /// The selected position or the selected item changed.
    private static func selectionChanged(from old: SwitcherSession, to new: SwitcherSession) -> Bool {
        if old.selectedIndex != new.selectedIndex { return true }
        return old.selectedItem?.id != new.selectedItem?.id
    }
}
