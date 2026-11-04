import Foundation

/// How old a window preview may be before it is refreshed, replaced or dropped. Times are
/// seconds on one monotonic clock; an image is stamped with the moment its capture
/// started (its content is at least that new).
public enum PreviewFreshness {
    /// While the switcher stays open and the selection rests, the selected window's large
    /// preview is captured again this often.
    public static let refreshInterval: TimeInterval = 2
    /// Failed refreshes back off (doubling) up to this interval.
    public static let maxRefreshInterval: TimeInterval = 16
    /// The sharp large-preview image stays in front of the small thumbnail unless the
    /// thumbnail was captured more than this much later. Covers a thumbnail batch that
    /// finishes just after the sharp capture, but not a sharp image left over from an
    /// earlier showing that could not be refreshed.
    public static let sharpPreferenceTolerance: TimeInterval = 3
    /// When capturing a window failed, its images older than this are dropped (the app
    /// icon shows) instead of standing in for the window indefinitely.
    public static let failedRefreshMaxAge: TimeInterval = 60

    /// Whether the sharp image (captured at `sharpCapturedAt`) should be shown rather than
    /// the thumbnail (captured at `thumbnailCapturedAt`, nil when there is none).
    public static func prefersSharp(sharpCapturedAt: TimeInterval, thumbnailCapturedAt: TimeInterval?) -> Bool {
        guard let thumbnailCapturedAt else { return true }
        return sharpCapturedAt >= thumbnailCapturedAt - sharpPreferenceTolerance
    }

    /// Whether an image captured at `incoming` may replace one captured at `existing`.
    /// A late result of an older capture never overwrites a newer image.
    public static func replaces(_ incoming: TimeInterval, existing: TimeInterval?) -> Bool {
        guard let existing else { return true }
        return incoming >= existing
    }

    /// Whether an image captured at `capturedAt` may still be shown at `now` after a
    /// capture of its window failed. A clock that went backwards keeps the image.
    public static func survivesFailedRefresh(capturedAt: TimeInterval, now: TimeInterval) -> Bool {
        now - capturedAt < failedRefreshMaxAge
    }

    /// Delay before the next refresh after `failures` consecutive failed captures of the
    /// same selection: `refreshInterval`, doubling per failure up to `maxRefreshInterval`.
    public static func refreshDelay(
        afterFailures failures: Int,
        interval: TimeInterval = refreshInterval,
        maxInterval: TimeInterval = maxRefreshInterval
    ) -> TimeInterval {
        let base = max(0.001, interval)
        let cap = max(base, maxInterval)
        var delay = base
        var remaining = max(0, failures)
        while remaining > 0, delay < cap {
            delay *= 2
            remaining -= 1
        }
        return min(delay, cap)
    }
}

/// Bounds native calls that may never answer (a screenshot or a window-list fetch).
///
/// At most `maxRunning` calls run at a time. A call that has not answered after `timeout`
/// is abandoned: its caller is told it failed and its slot is reused, but it still counts
/// as abandoned until it does answer. While `maxAbandoned` or more calls are abandoned,
/// nothing new starts, so a hung system service is never flooded with replacements: at
/// most `maxRunning + maxAbandoned - 1` calls are ever outstanding. A late answer to an
/// abandoned call is reported as `.late` and must be ignored.
public struct CaptureWorkLimiter: Equatable, Sendable {
    public enum Finish: Equatable, Sendable {
        /// Answered in time: use the result.
        case onTime
        /// Answered after it was abandoned: its caller was already told it failed.
        case late
        /// Not a call this limiter knows (already finished).
        case unknown
    }

    public let maxRunning: Int
    public let maxAbandoned: Int
    public let timeout: TimeInterval
    /// Running calls by ticket, with their start times.
    private var running: [Int: TimeInterval] = [:]
    private var abandoned: Set<Int> = []
    private var nextTicket = 1

    public init(maxRunning: Int, maxAbandoned: Int, timeout: TimeInterval) {
        self.maxRunning = max(1, maxRunning)
        self.maxAbandoned = max(1, maxAbandoned)
        self.timeout = max(0.001, timeout)
    }

    public var runningCount: Int { running.count }
    public var abandonedCount: Int { abandoned.count }

    /// Too many calls never answered: start nothing until some of them do.
    public var isSaturated: Bool { abandoned.count >= maxAbandoned }

    public var canStart: Bool { !isSaturated && running.count < maxRunning }

    /// Starts a call at `now`; nil when no slot is free.
    public mutating func start(at now: TimeInterval) -> Int? {
        guard canStart else { return nil }
        let ticket = nextTicket
        nextTicket += 1
        running[ticket] = now
        return ticket
    }

    /// The call answered.
    public mutating func finish(_ ticket: Int) -> Finish {
        if running.removeValue(forKey: ticket) != nil { return .onTime }
        if abandoned.remove(ticket) != nil { return .late }
        return .unknown
    }

    /// Abandons running calls older than `timeout` at `now`; returns their tickets, oldest
    /// first. Their callers must be told they failed.
    public mutating func expire(at now: TimeInterval) -> [Int] {
        let overdue = running.filter { now - $0.value >= timeout }.sorted { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }
        for (ticket, _) in overdue {
            running.removeValue(forKey: ticket)
            abandoned.insert(ticket)
        }
        return overdue.map(\.key)
    }

    /// Abandons one running call now, whatever its age. Returns false when it is not running.
    public mutating func abandon(_ ticket: Int) -> Bool {
        guard running.removeValue(forKey: ticket) != nil else { return false }
        abandoned.insert(ticket)
        return true
    }

    /// When the oldest running call times out, or nil when nothing runs.
    public var nextDeadline: TimeInterval? {
        running.values.min().map { $0 + timeout }
    }
}
