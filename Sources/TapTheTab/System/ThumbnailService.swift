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

    /// One window to capture, waiting for a free slot.
    private struct Job {
        let window: AnyObject
        let maxPixelSize: Int
        let storeInCache: Bool
        let token: Int
        let request: Request
    }

    /// One `capture` call: delivers per window, then finishes once.
    private final class Request {
        let deliver: (UInt32, CGImage) -> Void
        let completion: (() -> Void)?
        var remaining: Int

        init(remaining: Int, deliver: @escaping (UInt32, CGImage) -> Void, completion: (() -> Void)?) {
            self.remaining = remaining
            self.deliver = deliver
            self.completion = completion
        }

        func finishOne() {
            remaining -= 1
            if remaining == 0 { completion?() }
        }
    }

    private var cache: [UInt32: Cached] = [:]
    private var generation = 0
    /// Captures waiting for a slot, in order; priority ones go first.
    private var queue: [Job] = []
    private var running = 0
    /// Screenshots taken at the same time. Opening the switcher asks for every visible
    /// window; a few at a time keeps the capture work (and memory for larger previews)
    /// bounded, and lets the large preview's capture jump the queue.
    private static let maxConcurrentCaptures = 4

    static func make() -> ThumbnailService? {
        if #available(macOS 14.0, *) { return ThumbnailService() }
        return nil
    }

    /// Cached image, if any, for instant display while a fresh capture runs.
    func cachedImage(for windowID: UInt32) -> CGImage? { cache[windowID]?.image }

    func clear() {
        cache.removeAll()
        shareableContent = nil
        cancelPending()
    }

    /// Drops cached images for windows that no longer exist.
    func prune(keeping ids: Set<UInt32>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    /// Cancels delivery of in-flight and queued captures (e.g. when the switcher closes).
    /// Their completions are not called.
    func cancelPending() {
        generation += 1
        queue.removeAll()
        contentFetchSerial += 1
        contentWaiters.removeAll()
    }

    /// The window list ScreenCaptureKit gave us last; asking for it costs tens of
    /// milliseconds, and the switcher asks several times while it's open.
    private var shareableContent: SCShareableContent?
    private var shareableContentDate = Date.distantPast
    private static let shareableContentLifetime: TimeInterval = 1.5
    /// Callers waiting for the window list being fetched (one fetch at a time).
    private var contentWaiters: [(SCShareableContent?) -> Void] = []
    private var contentFetchSerial = 0

    /// Captures each window at most `maxPixelSize` on its long edge, and never larger than
    /// the window's own pixels. `deliver` runs on the main thread once per window that
    /// could be captured; `completion` runs once after every window was tried, unless
    /// `cancelPending()`/`clear()` dropped the request. With `storeInCache` false the image
    /// is only delivered (used for the large preview, so big images of every window ever
    /// selected don't pile up here). `priority` captures go ahead of queued ones.
    func capture(
        windowIDs: [UInt32],
        maxPixelSize: Int,
        storeInCache: Bool = true,
        priority: Bool = false,
        deliver: @escaping (UInt32, CGImage) -> Void,
        completion: (() -> Void)? = nil
    ) {
        guard #available(macOS 14.0, *), !windowIDs.isEmpty else {
            completion?()
            return
        }
        // Overlapping requests all deliver; only cancelPending()/clear() drop them.
        let token = generation
        let wanted = Set(windowIDs)
        withShareableContent(covering: wanted) { [weak self] content in
            guard let self, self.generation == token else { return }
            var order: [UInt32: Int] = [:]
            for (index, id) in windowIDs.enumerated() where order[id] == nil { order[id] = index }
            let windows = (content?.windows.filter { wanted.contains($0.windowID) } ?? [])
                .sorted { (order[$0.windowID] ?? 0) < (order[$1.windowID] ?? 0) }
            guard !windows.isEmpty else {
                completion?()
                return
            }
            let request = Request(remaining: windows.count, deliver: deliver, completion: completion)
            let jobs = windows.map {
                Job(window: $0, maxPixelSize: maxPixelSize, storeInCache: storeInCache, token: token, request: request)
            }
            if priority {
                self.queue.insert(contentsOf: jobs, at: 0)
            } else {
                self.queue.append(contentsOf: jobs)
            }
            self.pump()
        }
    }

    /// Starts queued captures while slots are free. Main thread only.
    private func pump() {
        guard #available(macOS 14.0, *) else { return }
        while running < Self.maxConcurrentCaptures, !queue.isEmpty {
            let job = queue.removeFirst()
            guard job.token == generation, let window = job.window as? SCWindow else { continue }
            running += 1
            start(job, window: window)
        }
    }

    @available(macOS 14.0, *)
    private func start(_ job: Job, window: SCWindow) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let frame = window.frame
        let longEdge = max(frame.width, frame.height, 1)
        // The frame is in points; on a Retina display the window has twice as many pixels.
        // Capping at points (scale 1) made large previews and peek look soft.
        let pixelsPerPoint = CGFloat(filter.pointPixelScale) > 0 ? CGFloat(filter.pointPixelScale) : 1
        let scale = min(pixelsPerPoint, CGFloat(job.maxPixelSize) / longEdge)
        configuration.width = max(1, Int((frame.width * scale).rounded()))
        configuration.height = max(1, Int((frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let windowID = window.windowID
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.running -= 1
                if job.token == self.generation {
                    if let image {
                        if job.storeInCache { self.cache[windowID] = Cached(image: image, date: Date()) }
                        job.request.deliver(windowID, image)
                    }
                    job.request.finishOne()
                }
                self.pump()
            }
        }
    }

    /// Calls `body` on the main thread with a recent window list that includes all of
    /// `windowIDs` (fetching a new one only when the cached one is old or incomplete), or
    /// with nil when ScreenCaptureKit could not list the windows.
    @available(macOS 14.0, *)
    private func withShareableContent(covering windowIDs: Set<UInt32>, _ body: @escaping (SCShareableContent?) -> Void) {
        if let content = shareableContent,
           Date().timeIntervalSince(shareableContentDate) < Self.shareableContentLifetime,
           windowIDs.isSubset(of: Set(content.windows.map(\.windowID))) {
            body(content)
            return
        }
        contentWaiters.append(body)
        // A fetch already running answers this caller too.
        guard contentWaiters.count == 1 else { return }
        let serial = contentFetchSerial
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self, self.contentFetchSerial == serial else { return }
                let fetched = error == nil ? content : nil
                if let fetched {
                    self.shareableContent = fetched
                    self.shareableContentDate = Date()
                }
                let waiters = self.contentWaiters
                self.contentWaiters.removeAll()
                for waiter in waiters { waiter(fetched) }
            }
        }
    }
}
