import AppKit
import ScreenCaptureKit
import TapTheTabCore

/// Window previews via ScreenCaptureKit (macOS 14+). Needs Screen Recording permission.
/// On macOS 13 `ThumbnailService.make()` returns nil and the switcher shows icons.
final class ThumbnailService {
    /// A captured image, stamped with the moment its capture started (system uptime) and
    /// the process that owned the window then (nil when ScreenCaptureKit did not say).
    struct Capture {
        let image: CGImage
        let capturedAt: TimeInterval
        let ownerPID: pid_t?
    }

    /// One window to capture, waiting for a free slot.
    private struct Job {
        let window: AnyObject
        let windowID: UInt32
        let maxPixelSize: Int
        let storeInCache: Bool
        let token: Int
        let request: Request
    }

    /// One `capture` call: delivers per window, then finishes once with the windows that
    /// could not be captured.
    private final class Request {
        let deliver: (UInt32, Capture) -> Void
        let completion: ((Set<UInt32>) -> Void)?
        var remaining: Int
        private var failed: Set<UInt32>

        init(remaining: Int, failed: Set<UInt32>, deliver: @escaping (UInt32, Capture) -> Void, completion: ((Set<UInt32>) -> Void)?) {
            self.remaining = remaining
            self.failed = failed
            self.deliver = deliver
            self.completion = completion
        }

        func finishOne(_ windowID: UInt32, captured: Bool) {
            if !captured { failed.insert(windowID) }
            remaining -= 1
            if remaining == 0 { completion?(failed) }
        }
    }

    private var cache: [UInt32: Capture] = [:]
    private var generation = 0
    /// Captures waiting for a slot, in order; priority ones go first.
    private var queue: [Job] = []
    /// Started captures by limiter ticket, until they answer or time out.
    private var inFlight: [Int: Job] = [:]
    /// Screenshots taken at the same time. Opening the switcher asks for every visible
    /// window; a few at a time keeps the capture work (and memory for larger previews)
    /// bounded, and lets the large preview's capture jump the queue. A screenshot that
    /// has not answered after `captureTimeout` counts as failed and frees its slot; once
    /// `maxAbandonedCaptures` such calls are outstanding nothing new starts (queued
    /// captures fail at once) until some answer, so at most seven calls are ever pending.
    private var captureLimiter = CaptureWorkLimiter(
        maxRunning: ThumbnailService.maxConcurrentCaptures,
        maxAbandoned: ThumbnailService.maxAbandonedCaptures,
        timeout: ThumbnailService.captureTimeout
    )
    private static let maxConcurrentCaptures = 4
    private static let maxAbandonedCaptures = 4
    private static let captureTimeout: TimeInterval = 3
    private var watchdogScheduled = false

    static func make() -> ThumbnailService? {
        if #available(macOS 14.0, *) { return ThumbnailService() }
        return nil
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Cached image, if any, for instant display while a fresh capture runs. Nil when the
    /// window number now belongs to another process than the one captured.
    func cachedImage(for windowID: UInt32, ownerPID: pid_t) -> Capture? {
        guard let cached = cache[windowID] else { return nil }
        if let owner = cached.ownerPID, owner != ownerPID {
            cache.removeValue(forKey: windowID)
            return nil
        }
        return cached
    }

    func clear() {
        cache.removeAll()
        shareableContent = nil
        cancelPending()
    }

    /// Drops cached images for windows that no longer exist or whose number now belongs
    /// to another process (`owners`: window number → owning process).
    func prune(keeping owners: [UInt32: pid_t]) {
        cache = cache.filter { id, cached in
            guard let owner = owners[id] else { return false }
            return cached.ownerPID.map { $0 == owner } ?? true
        }
    }

    /// Cancels delivery of in-flight and queued captures (e.g. when the switcher closes).
    /// Their completions are not called. A window-list fetch already running keeps going
    /// and answers the next callers.
    func cancelPending() {
        generation += 1
        queue.removeAll()
        contentWaiters.removeAll()
    }

    /// The window list ScreenCaptureKit gave us last; asking for it costs tens of
    /// milliseconds, and the switcher asks several times while it's open.
    private var shareableContent: SCShareableContent?
    private var shareableContentDate: TimeInterval = -.infinity
    private static let shareableContentLifetime: TimeInterval = 1.5
    /// Callers waiting for the window list being fetched (one fetch at a time).
    private var contentWaiters: [(SCShareableContent?) -> Void] = []
    /// The fetch being waited for. One that has not answered after `fetchTimeout` fails
    /// its waiters; one such fetch may stay outstanding before callers fail at once.
    private var contentFetchTicket: Int?
    private var contentLimiter = CaptureWorkLimiter(maxRunning: 1, maxAbandoned: 1, timeout: ThumbnailService.fetchTimeout)
    private static let fetchTimeout: TimeInterval = 3

    /// Captures each window at most `maxPixelSize` on its long edge, and never larger than
    /// the window's own pixels. `deliver` runs on the main thread once per window that
    /// could be captured; `completion` runs once after every window was tried, with the
    /// windows that could not be captured (not listed, no image, or timed out), unless
    /// `cancelPending()`/`clear()` dropped the request. With `storeInCache` false the image
    /// is only delivered (used for the large preview, so big images of every window ever
    /// selected don't pile up here). `priority` captures go ahead of queued ones.
    func capture(
        windowIDs: [UInt32],
        maxPixelSize: Int,
        storeInCache: Bool = true,
        priority: Bool = false,
        deliver: @escaping (UInt32, Capture) -> Void,
        completion: ((Set<UInt32>) -> Void)? = nil
    ) {
        guard #available(macOS 14.0, *), !windowIDs.isEmpty else {
            completion?(Set(windowIDs))
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
            let missing = wanted.subtracting(windows.map(\.windowID))
            // A window that is no longer listed has nothing current to show.
            for id in missing { self.dropStaleCache(for: id) }
            guard !windows.isEmpty else {
                completion?(missing)
                return
            }
            let request = Request(remaining: windows.count, failed: missing, deliver: deliver, completion: completion)
            let jobs = windows.map {
                Job(window: $0, windowID: $0.windowID, maxPixelSize: maxPixelSize, storeInCache: storeInCache,
                    token: token, request: request)
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
        // A full set of slots can leave jobs queued. Arm the watchdog on that exit too,
        // otherwise the callbacks it is meant to guard could keep the queue stuck.
        defer { scheduleWatchdog() }
        while !queue.isEmpty {
            if captureLimiter.isSaturated {
                // Screenshots stopped answering: fail what waits instead of leaving it queued.
                let waiting = queue
                queue.removeAll()
                for job in waiting where job.token == generation { fail(job) }
                return
            }
            guard captureLimiter.canStart else { return }
            let job = queue.removeFirst()
            guard job.token == generation else { continue }
            guard let window = job.window as? SCWindow,
                  let ticket = captureLimiter.start(at: Self.now) else {
                fail(job)
                continue
            }
            inFlight[ticket] = job
            start(job, window: window, ticket: ticket)
        }
    }

    @available(macOS 14.0, *)
    private func start(_ job: Job, window: SCWindow, ticket: Int) {
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
        let ownerPID = window.owningApplication?.processID
        let startedAt = Self.now
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let finish = self.captureLimiter.finish(ticket)
                self.inFlight.removeValue(forKey: ticket)
                defer { self.pump() }
                // A late answer was already reported as failed by the watchdog.
                guard finish == .onTime, job.token == self.generation else { return }
                guard let image else {
                    self.fail(job)
                    return
                }
                let capture = Capture(image: image, capturedAt: startedAt, ownerPID: ownerPID)
                if job.storeInCache, PreviewFreshness.replaces(startedAt, existing: self.cache[windowID]?.capturedAt) {
                    self.cache[windowID] = capture
                }
                job.request.deliver(windowID, capture)
                job.request.finishOne(windowID, captured: true)
            }
        }
    }

    /// A window could not be captured: report it, and forget a cached image too old to
    /// keep standing in for it.
    private func fail(_ job: Job) {
        dropStaleCache(for: job.windowID)
        job.request.finishOne(job.windowID, captured: false)
    }

    private func dropStaleCache(for windowID: UInt32) {
        guard let cached = cache[windowID],
              !PreviewFreshness.survivesFailedRefresh(capturedAt: cached.capturedAt, now: Self.now) else { return }
        cache.removeValue(forKey: windowID)
    }

    /// One timer at a time, for the oldest running screenshot's deadline.
    private func scheduleWatchdog() {
        guard !watchdogScheduled, let deadline = captureLimiter.nextDeadline else { return }
        watchdogScheduled = true
        let delay = max(0.01, deadline - Self.now)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.watchdogScheduled = false
            self.expireOverdueCaptures()
        }
    }

    private func expireOverdueCaptures() {
        let overdue = captureLimiter.expire(at: Self.now)
        if !overdue.isEmpty {
            Log.app.notice("Window capture timed out (\(overdue.count, privacy: .public)); \(self.captureLimiter.abandonedCount, privacy: .public) outstanding")
        }
        for ticket in overdue {
            guard let job = inFlight.removeValue(forKey: ticket), job.token == generation else { continue }
            fail(job)
        }
        pump()
    }

    /// Calls `body` on the main thread with a recent window list that includes all of
    /// `windowIDs` (fetching a new one only when the cached one is old or incomplete), or
    /// with nil when ScreenCaptureKit could not list the windows in time.
    @available(macOS 14.0, *)
    private func withShareableContent(covering windowIDs: Set<UInt32>, _ body: @escaping (SCShareableContent?) -> Void) {
        if let content = shareableContent,
           Self.now - shareableContentDate < Self.shareableContentLifetime,
           windowIDs.isSubset(of: Set(content.windows.map(\.windowID))) {
            body(content)
            return
        }
        contentWaiters.append(body)
        // A fetch already running answers this caller too.
        guard contentFetchTicket == nil else { return }
        guard let ticket = contentLimiter.start(at: Self.now) else {
            // An earlier fetch never answered: fail now rather than pile up more.
            finishContentWaiters(nil)
            return
        }
        contentFetchTicket = ticket
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let finish = self.contentLimiter.finish(ticket)
                // A late answer's waiters were already failed by the timeout.
                guard finish == .onTime, self.contentFetchTicket == ticket else { return }
                let fetched = error == nil ? content : nil
                if let fetched {
                    self.shareableContent = fetched
                    self.shareableContentDate = Self.now
                }
                self.contentFetchTicket = nil
                self.finishContentWaiters(fetched)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fetchTimeout) { [weak self] in
            guard let self, self.contentFetchTicket == ticket, self.contentLimiter.abandon(ticket) else { return }
            Log.app.notice("Window list for previews timed out")
            self.contentFetchTicket = nil
            self.finishContentWaiters(nil)
        }
    }

    private func finishContentWaiters(_ content: SCShareableContent?) {
        let waiters = contentWaiters
        contentWaiters.removeAll()
        for waiter in waiters { waiter(content) }
    }
}
