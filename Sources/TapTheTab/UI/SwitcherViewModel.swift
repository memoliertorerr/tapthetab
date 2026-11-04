import AppKit
import SwiftUI
import TapTheTabCore
import UniformTypeIdentifiers

/// A window preview and where it came from: when its capture started (system uptime) and
/// the process that owned the window (nil when unknown). The times decide which of two
/// images is newer and when an image is too old to keep after a failed capture.
struct PreviewImage {
    let image: CGImage
    let capturedAt: TimeInterval
    let ownerPID: Int32?

    init(image: CGImage, capturedAt: TimeInterval = ProcessInfo.processInfo.systemUptime, ownerPID: Int32? = nil) {
        self.image = image
        self.capturedAt = capturedAt
        self.ownerPID = ownerPID
    }

    /// Captured from a window now owned by another process (the number was reused).
    func isFromAnotherOwner(than pid: Int32?) -> Bool {
        guard let ownerPID, let pid else { return false }
        return ownerPID != pid
    }
}

/// State behind the switcher panel. Owned by `SwitcherPanelController`.
@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published private(set) var session: SwitcherSession = SwitcherSession(items: [])
    @Published private(set) var appearance: Appearance = Appearance()
    @Published private(set) var behavior: Behavior = Behavior()
    @Published private(set) var layout: SwitcherLayout = SwitcherLayout.initial
    @Published private(set) var thumbnails: [ItemID: CGImage] = [:]
    /// Capture time and owner of each thumbnail. Not published: it changes with `thumbnails`.
    private var thumbnailInfo: [ItemID: (capturedAt: TimeInterval, ownerPID: Int32?)] = [:]
    /// Sharper images for the large preview, a few recent ones. Observed only by the
    /// preview card, so a sharp image arriving does not redraw the grid or list.
    let largePreviews = LargePreviewStore()
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
    private var lastSelectionChange: TimeInterval?
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
        lastSelectionChange = nil
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
            thumbnailInfo = thumbnailInfo.filter { ids.contains($0.key) }
            largePreviews.prune(keeping: ids)
            discardImagesOfReusedWindows(in: session.items)
        } else {
            if !thumbnails.isEmpty { thumbnails = [:] }
            thumbnailInfo.removeAll()
            largePreviews.removeAll()
        }

        if self.appearance != appearance { self.appearance = appearance }
        if self.behavior != behavior { self.behavior = behavior }
        if self.layout != layout { self.layout = layout }
        if self.triggerModifiers != triggerModifiers { self.triggerModifiers = triggerModifiers }
        setPinnedBundleIDs(pinnedBundleIDs)
        self.session = session
        largePreviews.selectedID = session.selectedItem?.id
        generation += 1
        resetHoverBaseline()
    }

    /// Only the selection moved (same items, query and layout): that change slides the
    /// highlight and reshapes the preview card when animations are on. Anything else is
    /// applied at once. Returns true when the change animates.
    @discardableResult
    func update(session: SwitcherSession, layout: SwitcherLayout) -> Bool {
        let selectionMoved = Self.selectionChanged(from: self.session, to: session)
        let now = ProcessInfo.processInfo.systemUptime
        let animateSelection = PreviewSelectionAnimation.shouldAnimate(
            enabled: animates, previousChange: lastSelectionChange, now: now
        )
        if selectionMoved {
            lastSelectionChange = now
            if !isForwardingPointerInput { lastKeyboardSelectionChange = now }
        }
        let sameContent = Self.sameContent(self.session, session)
        // Windows that closed take their sharp images with them; a window number that now
        // belongs to another app takes its images too.
        if !sameContent { largePreviews.prune(keeping: Set(session.items.map(\.id))) }
        if !sameContent || self.session.items != session.items { discardImagesOfReusedWindows(in: session.items) }
        largePreviews.selectedID = session.selectedItem?.id
        if selectionMoved, animateSelection, self.layout == layout, sameContent {
            withAnimation(Self.selectionAnimation) {
                self.session = session
            }
            return true
        }
        withoutAnimation {
            if self.layout != layout { self.layout = layout }
            if self.session != session { self.session = session }
        }
        return false
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

    /// Images that arrive (or go) replace what is shown at once, never animated: inside an
    /// animation SwiftUI would crossfade the old and new image, which read as a slow blur
    /// turning sharp and, while cycling, stacked several large images being blended.
    /// An image captured now, from an unknown owner (used by `ScreenshotRenderer`).
    func setThumbnail(_ image: CGImage?, for id: ItemID) {
        setThumbnails([id: image.map { PreviewImage(image: $0) }])
    }

    /// Several thumbnails in one change, so the panels redraw once for all of them. An
    /// image older than the one shown (a late result) is ignored; nil removes.
    func setThumbnails(_ images: [ItemID: PreviewImage?]) {
        guard appearance.showPreviews, !images.isEmpty else { return }
        var updated = thumbnails
        var changed = false
        for (id, preview) in images {
            if let preview {
                guard !preview.isFromAnotherOwner(than: session.items.first(where: { $0.id == id })?.pid) else { continue }
                guard PreviewFreshness.replaces(preview.capturedAt, existing: thumbnailInfo[id]?.capturedAt) else { continue }
                updated[id] = preview.image
                thumbnailInfo[id] = (preview.capturedAt, preview.ownerPID)
                changed = true
            } else if updated.removeValue(forKey: id) != nil {
                thumbnailInfo.removeValue(forKey: id)
                changed = true
            }
        }
        guard changed else { return }
        withoutAnimation {
            thumbnails = updated
        }
    }

    func clearThumbnails() {
        if !thumbnails.isEmpty { thumbnails = [:] }
        thumbnailInfo.removeAll()
        largePreviews.removeAll()
    }

    /// A sharp image for the large preview. Kept even when the window is no longer
    /// selected (a late result while cycling), so going back to it is sharp at once;
    /// `LargePreviewStore` bounds how many are kept and ignores older results.
    func setLargePreview(_ preview: PreviewImage?, for id: ItemID) {
        guard appearance.showPreviews else { return }
        if let preview, preview.isFromAnotherOwner(than: session.items.first(where: { $0.id == id })?.pid) { return }
        withoutAnimation {
            if let preview {
                largePreviews.store(preview, for: id)
            } else {
                largePreviews.remove(id)
            }
        }
    }

    /// Capturing these windows failed at `now`: their images too old to keep standing in
    /// for them (`PreviewFreshness.failedRefreshMaxAge`) are dropped, so the card shows
    /// the app icon rather than a frozen picture. Returns true when anything was dropped.
    @discardableResult
    func discardStaleImages(for ids: Set<ItemID>, now: TimeInterval) -> Bool {
        guard !ids.isEmpty else { return false }
        var updated = thumbnails
        for id in ids {
            guard let info = thumbnailInfo[id],
                  !PreviewFreshness.survivesFailedRefresh(capturedAt: info.capturedAt, now: now) else { continue }
            updated.removeValue(forKey: id)
            thumbnailInfo.removeValue(forKey: id)
        }
        var dropped = false
        withoutAnimation {
            if updated.count != thumbnails.count {
                thumbnails = updated
                dropped = true
            }
            for id in ids {
                guard let sharp = largePreviews.entry(for: id),
                      !PreviewFreshness.survivesFailedRefresh(capturedAt: sharp.capturedAt, now: now) else { continue }
                largePreviews.remove(id)
                dropped = true
            }
        }
        return dropped
    }

    /// Drops images captured from a window whose number now belongs to another process.
    private func discardImagesOfReusedWindows(in items: [SwitcherItem]) {
        guard !thumbnailInfo.isEmpty || !largePreviews.isEmpty else { return }
        var owners: [ItemID: Int32] = [:]
        for item in items { owners[item.id] = item.pid }
        let reused = thumbnailInfo.compactMap { id, info -> ItemID? in
            guard let owner = info.ownerPID, let pid = owners[id], owner != pid else { return nil }
            return id
        }
        withoutAnimation {
            if !reused.isEmpty {
                var updated = thumbnails
                for id in reused {
                    updated.removeValue(forKey: id)
                    thumbnailInfo.removeValue(forKey: id)
                }
                thumbnails = updated
            }
            largePreviews.discard { id, preview in preview.isFromAnotherOwner(than: owners[id]) }
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
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

    /// The large preview's image, when the layout has room for it: the selected window's
    /// sharp image, else its thumbnail (scaled up until the sharp one arrives).
    var selectedPreview: CGImage? {
        guard layout.showsPreview, appearance.showPreviews, let id = session.selectedItem?.id else { return nil }
        return shownSharpImage(for: id) ?? thumbnails[id]
    }

    /// The sharp image of `id` when it should be shown: unless the thumbnail is clearly
    /// newer (a sharp image that could not be refreshed must not hide a fresh thumbnail).
    private func shownSharpImage(for id: ItemID) -> CGImage? {
        guard let sharp = largePreviews.entry(for: id) else { return nil }
        let thumbnailCapturedAt = thumbnails[id] == nil ? nil : thumbnailInfo[id]?.capturedAt
        guard PreviewFreshness.prefersSharp(sharpCapturedAt: sharp.capturedAt, thumbnailCapturedAt: thumbnailCapturedAt) else {
            return nil
        }
        return sharp.image
    }

    /// Ignore image-rounding differences, but follow the sharp capture when a cached
    /// thumbnail has stale proportions after the window was resized.
    var previewCardSize: CGSize {
        guard layout.showsPreview, let id = session.selectedItem?.id else { return .zero }
        let thumbnail = thumbnails[id].map { Size(width: Double($0.width), height: Double($0.height)) }
        let sharp = shownSharpImage(for: id).map { Size(width: Double($0.width), height: Double($0.height)) }
        return CGSize(layout.core.previewCardSize(thumbnail: thumbnail, sharp: sharp))
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

/// The large preview's sharp images: the selected window's and a few recently captured
/// others (`PreviewImageRetention` bounds them by count and pixels). Changes publish only
/// when they alter the selected window's image, so late results for windows cycled past
/// cost no redraw.
@MainActor
final class LargePreviewStore: ObservableObject {
    private var images: [ItemID: PreviewImage] = [:]
    private var retention = PreviewImageRetention<ItemID>()

    /// The selected window, which is never dropped to make room. Set by the model; not
    /// published (the session change that moves the selection redraws already).
    var selectedID: ItemID? {
        didSet {
            if let selectedID, selectedID != oldValue { retention.touch(selectedID) }
        }
    }

    func image(for id: ItemID) -> CGImage? { images[id]?.image }

    func entry(for id: ItemID) -> PreviewImage? { images[id] }

    var isEmpty: Bool { images.isEmpty }

    /// Stores `preview` unless the stored image of `id` is newer (a late result).
    func store(_ preview: PreviewImage, for id: ItemID) {
        guard PreviewFreshness.replaces(preview.capturedAt, existing: images[id]?.capturedAt) else { return }
        if id == selectedID { objectWillChange.send() }
        images[id] = preview
        let image = preview.image
        for dropped in retention.insert(id, pixels: image.width * image.height, protecting: selectedID) {
            images.removeValue(forKey: dropped)
        }
    }

    /// Drops the images `shouldDrop` picks.
    func discard(where shouldDrop: (ItemID, PreviewImage) -> Bool) {
        let dropped = images.filter { shouldDrop($0.key, $0.value) }.map(\.key)
        for id in dropped { remove(id) }
    }

    func remove(_ id: ItemID) {
        guard images[id] != nil else { return }
        if id == selectedID { objectWillChange.send() }
        images.removeValue(forKey: id)
        retention.remove(id)
    }

    /// Keeps only images of windows in `ids`.
    func prune(keeping ids: Set<ItemID>) {
        let dropped = retention.prune(keeping: ids)
        guard !dropped.isEmpty else { return }
        if let selectedID, dropped.contains(selectedID) { objectWillChange.send() }
        for id in dropped { images.removeValue(forKey: id) }
    }

    func removeAll() {
        guard !images.isEmpty else { return }
        objectWillChange.send()
        images.removeAll()
        retention.removeAll()
    }
}
