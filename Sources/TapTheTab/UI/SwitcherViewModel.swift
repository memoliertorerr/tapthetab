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
    /// Bumped on every show so scroll views start fresh.
    @Published private(set) var generation: Int = 0

    var inputHandler: ((SwitcherInput) -> Void)?

    private var iconCache: [Int32: NSImage] = [:]
    /// Mouse position when hover last counted (or when the panel appeared / relaid out).
    /// Hover only selects once the mouse has really moved, so a panel appearing under a
    /// resting pointer does not steal the selection.
    private var hoverBaseline: NSPoint?

    private lazy var genericAppIcon: NSImage = NSWorkspace.shared.icon(for: UTType.application)

    func present(session: SwitcherSession, appearance: Appearance, behavior: Behavior, layout: SwitcherLayout) {
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
        self.session = session
        generation += 1
        resetHoverBaseline()
    }

    func update(session: SwitcherSession, layout: SwitcherLayout) {
        if self.layout != layout { self.layout = layout }
        if self.session != session { self.session = session }
    }

    func setThumbnail(_ image: CGImage?, for id: ItemID) {
        guard appearance.showPreviews else { return }
        if let image {
            thumbnails[id] = image
        } else if thumbnails[id] != nil {
            thumbnails.removeValue(forKey: id)
        }
    }

    func clearThumbnails() {
        if !thumbnails.isEmpty { thumbnails = [:] }
    }

    func thumbnail(for id: ItemID) -> CGImage? {
        guard appearance.showPreviews else { return nil }
        return thumbnails[id]
    }

    /// Cached per process; not published, so filling the cache during rendering is fine.
    func icon(for pid: Int32) -> NSImage {
        if let cached = iconCache[pid] { return cached }
        let image: NSImage = NSRunningApplication(processIdentifier: pid)?.icon ?? genericAppIcon
        iconCache[pid] = image
        return image
    }

    func resetHoverBaseline() {
        hoverBaseline = NSEvent.mouseLocation
    }

    func hover(index: Int, inside: Bool) {
        guard inside, behavior.mouseHoverSelects else { return }
        let location: NSPoint = NSEvent.mouseLocation
        if let baseline = hoverBaseline, baseline == location { return }
        hoverBaseline = location
        guard index != session.selectedIndex else { return }
        inputHandler?(.select(index: index))
    }

    func click(index: Int) {
        inputHandler?(.select(index: index))
        inputHandler?(.commit)
    }
}
