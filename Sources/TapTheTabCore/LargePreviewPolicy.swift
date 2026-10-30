import Foundation

/// When to capture the sharper image of the selected window for the large preview.
///
/// One capture runs at a time. A selection change after a pause starts a capture at once
/// (or right after the one running); while the selection moves quickly (⇥ held or tapped
/// fast) the capture waits until the selection has rested for `settleDelay`, so cycling
/// doesn't queue a screenshot per step. Times are seconds on one monotonic clock.
public struct LargePreviewCaptureSchedule: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        /// Nothing to start now (a capture is running and will be followed by another).
        case none
        /// Start a capture of the current selection; report back with `captureFinished`.
        case captureNow
        /// Call `timerFired` after this many seconds unless the selection changes again.
        case wait(TimeInterval)
    }

    /// Selection changes closer together than this count as cycling.
    public static let cyclingInterval: TimeInterval = 0.12
    /// While cycling, how long the selection must rest before a capture starts.
    public static let settleDelay: TimeInterval = 0.08
    /// A capture that has not reported back after this long no longer blocks the next one.
    public static let captureTimeout: TimeInterval = 1

    private var lastChange: TimeInterval?
    private var captureStartedAt: TimeInterval?
    /// The selection changed while a capture was running: capture again when it ends.
    private var capturesAgain = false

    public init() {}

    /// A capture was started and has not finished (or timed out) at `now`.
    public func isCapturing(at now: TimeInterval) -> Bool {
        guard let start = captureStartedAt else { return false }
        return now - start < Self.captureTimeout
    }

    /// The selection changed (or the switcher appeared) at `now`. Any timer from an earlier
    /// decision should be cancelled; this decision replaces it.
    public mutating func selectionChanged(at now: TimeInterval) -> Decision {
        let cycling = lastChange.map { now - $0 >= 0 && now - $0 < Self.cyclingInterval } ?? false
        lastChange = now
        if cycling {
            // The timer will ask again once the selection rests.
            capturesAgain = false
            return .wait(Self.settleDelay)
        }
        return startOrQueue(at: now)
    }

    /// The delay from a `.wait` decision ran out at `now`.
    public mutating func timerFired(at now: TimeInterval) -> Decision {
        startOrQueue(at: now)
    }

    /// The running capture delivered its image or failed.
    public mutating func captureFinished(at now: TimeInterval) -> Decision {
        captureStartedAt = nil
        guard capturesAgain else { return .none }
        capturesAgain = false
        captureStartedAt = now
        return .captureNow
    }

    private mutating func startOrQueue(at now: TimeInterval) -> Decision {
        if isCapturing(at: now) {
            capturesAgain = true
            return .wait(max(0.001, Self.captureTimeout - (now - (captureStartedAt ?? now))))
        }
        capturesAgain = false
        captureStartedAt = now
        return .captureNow
    }
}

/// Which sharp large-preview images to keep in memory: the most recently used, at most
/// `maxCount` of them and `maxPixels` pixels together. The newest image and the protected
/// one (the selected window's) are never dropped, so one image larger than the budget is
/// still shown. Revisiting a window while cycling then shows it sharp at once.
public struct PreviewImageRetention<Key: Hashable & Sendable>: Equatable, Sendable {
    public let maxCount: Int
    public let maxPixels: Int
    /// Least recently used first.
    public private(set) var keys: [Key] = []
    private var pixelCounts: [Key: Int] = [:]

    public init(maxCount: Int = 3, maxPixels: Int = 16_000_000) {
        self.maxCount = max(1, maxCount)
        self.maxPixels = max(0, maxPixels)
    }

    public var totalPixels: Int { pixelCounts.values.reduce(0, +) }

    public func contains(_ key: Key) -> Bool { pixelCounts[key] != nil }

    /// Records an image of `pixels` pixels stored (or replaced) for `key`, now the most
    /// recent. Returns the keys whose images must be dropped to stay within the limits.
    public mutating func insert(_ key: Key, pixels: Int, protecting protected: Key? = nil) -> [Key] {
        keys.removeAll { $0 == key }
        keys.append(key)
        pixelCounts[key] = max(0, pixels)
        var dropped: [Key] = []
        while keys.count > maxCount || totalPixels > maxPixels {
            guard let index = keys.firstIndex(where: { $0 != key && $0 != protected }) else { break }
            let victim = keys.remove(at: index)
            pixelCounts.removeValue(forKey: victim)
            dropped.append(victim)
        }
        return dropped
    }

    /// Marks `key` as the most recently used (selected again). Nothing when absent.
    public mutating func touch(_ key: Key) {
        guard contains(key) else { return }
        keys.removeAll { $0 == key }
        keys.append(key)
    }

    public mutating func remove(_ key: Key) {
        keys.removeAll { $0 == key }
        pixelCounts.removeValue(forKey: key)
    }

    /// Drops every key not in `kept` (windows that closed); returns the dropped keys.
    public mutating func prune(keeping kept: Set<Key>) -> [Key] {
        let dropped = keys.filter { !kept.contains($0) }
        guard !dropped.isEmpty else { return [] }
        keys.removeAll { !kept.contains($0) }
        for key in dropped { pixelCounts.removeValue(forKey: key) }
        return dropped
    }

    public mutating func removeAll() {
        keys.removeAll()
        pixelCounts.removeAll()
    }
}

/// Rapid keyboard cycling must not queue overlapping selection springs. Slow steps
/// retain the configured motion; rapid steps snap directly to the latest selection.
public enum PreviewSelectionAnimation {
    public static let minimumInterval: TimeInterval = 0.12

    public static func shouldAnimate(enabled: Bool, previousChange: TimeInterval?, now: TimeInterval) -> Bool {
        guard enabled else { return false }
        guard let previousChange else { return true }
        return now - previousChange >= minimumInterval
    }
}

/// A window and the resolution last requested for its large preview. Keeping the same
/// selection needs another capture when filtering makes its preview box larger.
public struct PreviewCaptureTarget: Equatable, Sendable {
    public let id: ItemID
    public let pixelSize: Int

    public init(id: ItemID, pixelSize: Int) {
        self.id = id
        self.pixelSize = pixelSize
    }

    public func requiresCapture(after previous: PreviewCaptureTarget?) -> Bool {
        guard let previous else { return true }
        return id != previous.id || pixelSize > previous.pixelSize
    }
}
