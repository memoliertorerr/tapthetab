import AppKit
import ScreenCaptureKit
import TapTheTabCore

/// Window previews via ScreenCaptureKit (macOS 14+). Needs Screen Recording permission.
/// On macOS 13 `ThumbnailService.make()` returns nil and the switcher shows icons.
final class ThumbnailService {
    private struct Cached {
        let image: CGImage
        let date: Date
    }

    private var cache: [UInt32: Cached] = [:]
    private var generation = 0

    static func make() -> ThumbnailService? {
        if #available(macOS 14.0, *) { return ThumbnailService() }
        return nil
    }

    /// Cached image, if any, for instant display while a fresh capture runs.
    func cachedImage(for windowID: UInt32) -> CGImage? { cache[windowID]?.image }

    func clear() {
        cache.removeAll()
        generation += 1
    }

    /// Drops cached images for windows that no longer exist.
    func prune(keeping ids: Set<UInt32>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    /// Cancels delivery of in-flight captures (e.g. when the switcher closes).
    func cancelPending() { generation += 1 }

    /// Captures each window at most `maxPixelSize` on its long edge. `deliver` runs on
    /// the main thread once per window that could be captured.
    func capture(windowIDs: [UInt32], maxPixelSize: Int, deliver: @escaping (UInt32, CGImage) -> Void) {
        guard #available(macOS 14.0, *), !windowIDs.isEmpty else { return }
        generation += 1
        let token = generation
        let wanted = Set(windowIDs)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let content, error == nil else { return }
            let windows = content.windows.filter { wanted.contains($0.windowID) }
            for window in windows {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                let frame = window.frame
                let longEdge = max(frame.width, frame.height, 1)
                let scale = min(1.0, CGFloat(maxPixelSize) / longEdge)
                configuration.width = max(1, Int(frame.width * scale))
                configuration.height = max(1, Int(frame.height * scale))
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let windowID = window.windowID
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                    guard let image else { return }
                    DispatchQueue.main.async {
                        guard let self, self.generation == token else { return }
                        self.cache[windowID] = Cached(image: image, date: Date())
                        deliver(windowID, image)
                    }
                }
            }
        }
    }
}
