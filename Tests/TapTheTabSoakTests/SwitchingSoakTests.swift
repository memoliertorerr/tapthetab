import XCTest
import TapTheTabCore
@testable import TapTheTabSoakSupport

/// Deterministic soak of the switching and preview-capture policies (see `SoakSimulation`).
/// Workloads are small so the suite stays fast; `make soak` runs larger ones locally. No
/// assertion depends on wall-clock time.
final class SwitchingSoakTests: XCTestCase {
    private static let workload = SoakWorkload(seed: 0x5EED_0001, sessions: 96, maxWindows: 60, maxSteps: 40)

    private func assertPassed(_ report: SoakReport, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(report.violationCount, 0, report.violations.joined(separator: "\n"), file: file, line: line)
    }

    func testEveryScenarioRunsAndEveryContractHolds() {
        let report = SoakSimulation.run(Self.workload)
        assertPassed(report)
        XCTAssertEqual(report.sessionsCompleted, 96)
        XCTAssertFalse(report.cancelled)
        for scenario in SoakScenario.allCases {
            XCTAssertEqual(report.sessionsByScenario[scenario], 12, scenario.rawValue)
        }
        // The stressful paths were reached, not only the happy one.
        XCTAssertGreaterThan(report.cyclingNotifications, 0, "rapid cycling")
        XCTAssertGreaterThan(report.deferredSelections, 0, "captures waited to settle or for a running one")
        XCTAssertGreaterThan(report.refreshAttempts, 0, "resting previews refreshed")
        XCTAssertGreaterThan(report.previewFailed, 0, "failed captures fed the back-off")
        XCTAssertGreaterThan(report.previewSkipped, 0, "minimized or hidden selections")
        XCTAssertGreaterThan(report.timedOut, 0, "screenshot watchdog fired")
        XCTAssertGreaterThan(report.answeredLate, 0, "late answers released abandoned calls")
        XCTAssertGreaterThan(report.failedWithoutStarting, 0, "the limit saturated")
        XCTAssertGreaterThan(report.windowListTimeouts, 0, "window-list watchdog fired")
        XCTAssertGreaterThan(report.windowListRefusals, 0, "a hung window-list fetch refused new ones")
        XCTAssertGreaterThan(report.supersededCompletions, 0, "out-of-order large-preview completions")
        XCTAssertGreaterThan(report.olderResultsRejected, 0, "older images arrived after newer ones")
        XCTAssertGreaterThan(report.closedSessionResultsDropped, 0, "results outlived their session")
        XCTAssertGreaterThan(report.imagesDroppedByRetention, 0, "retention limits applied")
        XCTAssertGreaterThan(report.catalogReplacements, 0, "windows changed mid-session")
        XCTAssertGreaterThan(report.windowActions, 0, "close, minimize, hide and quit")
        // Bounds observed, not only asserted inside the run.
        XCTAssertGreaterThan(report.maxOutstandingNativeCalls, SoakAppLimits.maxRunningCaptures, "abandoned calls stayed counted")
        XCTAssertLessThanOrEqual(report.maxOutstandingNativeCalls, SoakAppLimits.maxOutstandingCaptures)
        XCTAssertLessThanOrEqual(report.maxRunningNativeCalls, SoakAppLimits.maxRunningCaptures)
        XCTAssertLessThanOrEqual(report.maxRetainedImages, SoakAppLimits.retainedImages)
        XCTAssertLessThanOrEqual(report.longestSelectionToAttempt, LargePreviewCaptureSchedule.settleDelay + LargePreviewCaptureSchedule.captureTimeout + 0.005)
    }

    func testTheSameSeedReproducesTheRunExactly() {
        let workload = SoakWorkload(seed: 42, sessions: 32, maxWindows: 40, maxSteps: 30)
        let first = SoakSimulation.run(workload)
        let second = SoakSimulation.run(workload)
        XCTAssertEqual(first, second)
        assertPassed(first)

        var other = workload
        other.seed = 43
        XCTAssertNotEqual(SoakSimulation.run(other).digest, first.digest, "a different seed is a different workload")
    }

    func testStoppingEarlyEndsBetweenSessionsAndStillDrainsLateWork() {
        var asked = 0
        let report = SoakSimulation.run(Self.workload) {
            asked += 1
            return asked < 10
        }
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(report.sessionsCompleted, 10)
        // The run's end checks (every abandoned call answered, limits unblocked, nothing
        // left open) still ran.
        assertPassed(report)
    }

    func testRepeatedQuickOpenAndCloseLeavesNothingBehind() {
        // Only sessions 8, 16, … are quick taps, but every one of the 200 sessions opens,
        // resets the schedule and closes; the run's end checks cover what they leave.
        let report = SoakSimulation.run(SoakWorkload(seed: 7, sessions: 200, maxWindows: 12, maxSteps: 3))
        assertPassed(report)
        XCTAssertEqual(report.sessionsCompleted, 200)
        XCTAssertLessThanOrEqual(report.retainedImagesAtEnd, SoakAppLimits.retainedImages)
    }

    func testLargeCatalogs() {
        let report = SoakSimulation.run(SoakWorkload(seed: 0xB16, sessions: 40, maxWindows: 1_500, maxSteps: 30))
        assertPassed(report)
        XCTAssertGreaterThan(report.largestCatalog, 200)
        XCTAssertGreaterThan(report.maxQueuedCaptures, SoakAppLimits.maxRunningCaptures)
    }

    func testWorkloadInputIsClamped() {
        let workload = SoakWorkload(seed: 1, sessions: 0, maxWindows: 1_000_000, maxSteps: -5)
        XCTAssertEqual(workload.sessions, SoakWorkload.sessionRange.lowerBound)
        XCTAssertEqual(workload.maxWindows, SoakWorkload.windowRange.upperBound)
        XCTAssertEqual(workload.maxSteps, SoakWorkload.stepRange.lowerBound)
    }

    // MARK: The checks catch broken policies

    func testCatchesACompletionThatReplacesTheSettleTimerWithARefresh() {
        // The regression once shipped: a capture finishing during cycling replaced the
        // 80 ms settle timer with the 2 s periodic refresh, so the final selection waited.
        var policies = SoakPolicies.production
        policies.makeSchedule = { SettleReplacingSchedule() }
        let report = SoakSimulation.run(Self.workload, policies: policies)
        XCTAssertTrue(report.violations.contains { $0.contains("not attempted within") }, report.violations.joined(separator: "\n"))
    }

    func testCatchesCapturesStartedWhileCycling() {
        var policies = SoakPolicies.production
        policies.makeSchedule = { NeverSettlingSchedule() }
        let report = SoakSimulation.run(Self.workload, policies: policies)
        XCTAssertTrue(report.violations.contains { $0.contains("before cycling settled") }, report.violations.joined(separator: "\n"))
    }

    func testCatchesALimiterThatForgetsAbandonedCalls() {
        var policies = SoakPolicies.production
        policies.makeLimiter = { ForgetfulLimiter(inner: CaptureWorkLimiter(maxRunning: $0, maxAbandoned: $1, timeout: $2)) }
        let report = SoakSimulation.run(Self.workload, policies: policies)
        XCTAssertTrue(report.violations.contains { $0.contains("screenshot calls outstanding") }, report.violations.joined(separator: "\n"))
    }

    func testCatchesRetentionThatNeverDropsImages() {
        var policies = SoakPolicies.production
        policies.makeRetention = { KeepEverythingRetention() }
        let report = SoakSimulation.run(Self.workload, policies: policies)
        XCTAssertTrue(report.violations.contains { $0.contains("large-preview images retained (limit") }, report.violations.joined(separator: "\n"))
    }

    func testCatchesAScreenshotWatchdogThatNeverExpiresCalls() {
        var policies = SoakPolicies.production
        policies.makeLimiter = { NeverExpiringLimiter(inner: CaptureWorkLimiter(maxRunning: $0, maxAbandoned: $1, timeout: $2)) }
        let report = SoakSimulation.run(SoakWorkload(seed: 7, sessions: 16, maxWindows: 12, maxSteps: 12), policies: policies)
        XCTAssertTrue(report.violations.contains { $0.contains("running screenshot exceeded watchdog deadline") }, report.violations.joined(separator: "\n"))
    }

    func testRecycledWindowIDsStayBoundedAndCanStillBeReused() {
        var pool = SoakWindowNumberPool()
        for number in 1...UInt32(SoakWindowNumberPool.capacity * 2) { pool.append(number) }
        XCTAssertEqual(pool.count, SoakWindowNumberPool.capacity)
        XCTAssertEqual(pool.remove(at: 0), 1)
        pool.append(999_999)
        XCTAssertEqual(pool.count, SoakWindowNumberPool.capacity)
        XCTAssertEqual(pool.remove(at: pool.count - 1), 999_999)
    }

    // MARK: Seeded properties of the production policies

    func testAHungServiceIsNeverGivenMoreThanSevenCalls() {
        // Requests trickling in one at a time reach the bound exactly; seeded bursts never
        // pass it. An hour of trying every 250 ms while nothing ever answers.
        let trickle = startsWhileHung { _ in 1 }
        XCTAssertEqual(trickle.started.count, SoakAppLimits.maxOutstandingCaptures)
        var random = SoakRandom(seed: 5)
        for _ in 0..<20 {
            let bursts = startsWhileHung { _ in random.int(0...6) }
            XCTAssertLessThanOrEqual(bursts.started.count, SoakAppLimits.maxOutstandingCaptures)
        }

        var limiter = trickle.limiter
        let started = trickle.started
        XCTAssertEqual(limiter.abandonedCount, started.count)
        XCTAssertTrue(limiter.isSaturated)

        // Answers arrive in a seeded random order; each releases its abandoned call once.
        random = SoakRandom(seed: 99)
        var pending = started
        while !pending.isEmpty {
            let ticket = pending.remove(at: random.int(0...(pending.count - 1)))
            XCTAssertEqual(limiter.finish(ticket), .late)
            XCTAssertEqual(limiter.finish(ticket), .unknown, "a second answer is not counted again")
        }
        XCTAssertEqual(limiter.abandonedCount, 0)
        XCTAssertTrue(limiter.canStart)
    }

    private func startsWhileHung(requests: (Int) -> Int) -> (limiter: CaptureWorkLimiter, started: [Int]) {
        var limiter = CaptureWorkLimiter(maxRunning: 4, maxAbandoned: 4, timeout: 3)
        var started: [Int] = []
        for tick in 0..<14_400 {
            let now = Double(tick) * 0.25
            _ = limiter.expire(at: now)
            for _ in 0..<requests(tick) {
                guard let ticket = limiter.start(at: now) else { break }
                started.append(ticket)
            }
        }
        return (limiter, started)
    }

    func testRetentionStaysBoundedUnderSeededRandomUse() {
        var retention = PreviewImageRetention<Int>(maxCount: 3, maxPixels: 16_000_000)
        var random = SoakRandom(seed: 2_024)
        var held: [Int: Int] = [:]
        for _ in 0..<20_000 {
            let key = random.int(0...24)
            switch random.int(0...9) {
            case 0...5:
                let pixels = random.chance(0.05) ? 30_000_000 : random.int(1...6_000_000)
                let protected: Int? = random.chance(0.7) ? random.int(0...24) : nil
                held[key] = pixels
                for dropped in retention.insert(key, pixels: pixels, protecting: protected) {
                    XCTAssertNotEqual(dropped, key, "the newest image is never dropped")
                    XCTAssertNotEqual(dropped, protected, "the protected image is never dropped")
                    XCTAssertNotNil(held.removeValue(forKey: dropped), "only held images are dropped")
                }
                XCTAssertLessThanOrEqual(retention.keys.count, 3)
                if retention.totalPixels > retention.maxPixels {
                    XCTAssertTrue(retention.keys.allSatisfy { $0 == key || $0 == protected }, "over budget only for exempt images")
                }
            case 6, 7:
                retention.touch(key)
            case 8:
                retention.remove(key)
                held.removeValue(forKey: key)
            default:
                let kept = Set((0...24).filter { _ in random.chance(0.8) })
                for dropped in retention.prune(keeping: kept) {
                    XCTAssertFalse(kept.contains(dropped))
                    XCTAssertNotNil(held.removeValue(forKey: dropped))
                }
            }
            XCTAssertEqual(Set(retention.keys), Set(held.keys), "drop lists name exactly what left")
            XCTAssertEqual(retention.totalPixels, held.values.reduce(0, +))
        }
    }
}

// MARK: - Deliberately broken policies

/// Reintroduces the settle-timer regression: a completion during cycling schedules the
/// periodic refresh instead of leaving the settle timer in charge.
private struct SettleReplacingSchedule: SoakCaptureScheduling {
    var inner = LargePreviewCaptureSchedule(refreshInterval: PreviewFreshness.refreshInterval)
    var needsCaptureRetry: Bool { inner.needsCaptureRetry }

    mutating func selectionChanged(at now: TimeInterval) -> LargePreviewCaptureSchedule.Decision {
        inner.selectionChanged(at: now)
    }

    mutating func timerFired(at now: TimeInterval) -> LargePreviewCaptureSchedule.Decision {
        inner.timerFired(at: now)
    }

    mutating func captureFinished(at now: TimeInterval, outcome: LargePreviewCaptureSchedule.Outcome) -> LargePreviewCaptureSchedule.Decision {
        let decision = inner.captureFinished(at: now, outcome: outcome)
        if decision == .none, outcome != .skipped, let delay = inner.nextRefreshDelay { return .wait(delay) }
        return decision
    }
}

/// Captures on every selection change, ignoring the settle delay while cycling.
private struct NeverSettlingSchedule: SoakCaptureScheduling {
    var inner = LargePreviewCaptureSchedule(refreshInterval: PreviewFreshness.refreshInterval)
    var needsCaptureRetry: Bool { inner.needsCaptureRetry }

    mutating func selectionChanged(at now: TimeInterval) -> LargePreviewCaptureSchedule.Decision {
        let decision = inner.selectionChanged(at: now)
        if decision == .wait(LargePreviewCaptureSchedule.settleDelay) { return inner.timerFired(at: now) }
        return decision
    }

    mutating func timerFired(at now: TimeInterval) -> LargePreviewCaptureSchedule.Decision {
        inner.timerFired(at: now)
    }

    mutating func captureFinished(at now: TimeInterval, outcome: LargePreviewCaptureSchedule.Outcome) -> LargePreviewCaptureSchedule.Decision {
        inner.captureFinished(at: now, outcome: outcome)
    }
}

/// Frees a timed-out call's slot without counting it as abandoned, so a hung service
/// keeps receiving replacements.
private struct ForgetfulLimiter: SoakWorkLimiting {
    var inner: CaptureWorkLimiter
    var forgotten: Set<Int> = []

    var nextDeadline: TimeInterval? { inner.nextDeadline }
    var isSaturated: Bool { inner.isSaturated }
    var canStart: Bool { inner.canStart }

    mutating func start(at now: TimeInterval) -> Int? { inner.start(at: now) }

    mutating func finish(_ ticket: Int) -> CaptureWorkLimiter.Finish {
        if forgotten.remove(ticket) != nil { return .late }
        return inner.finish(ticket)
    }

    mutating func expire(at now: TimeInterval) -> [Int] {
        let overdue = inner.expire(at: now)
        for ticket in overdue {
            _ = inner.finish(ticket)
            forgotten.insert(ticket)
        }
        return overdue
    }

    mutating func abandon(_ ticket: Int) -> Bool {
        guard inner.abandon(ticket) else { return false }
        _ = inner.finish(ticket)
        forgotten.insert(ticket)
        return true
    }
}

/// Never drops an image.
private struct KeepEverythingRetention: SoakImageRetaining {
    mutating func insert(_ key: ItemID, pixels: Int, protecting protected: ItemID?) -> [ItemID] { [] }
    mutating func touch(_ key: ItemID) {}
    mutating func remove(_ key: ItemID) {}
    mutating func prune(keeping kept: Set<ItemID>) -> [ItemID] { [] }
}

/// Leaves calls marked running past their deadline, while all other limiter behavior stays.
private struct NeverExpiringLimiter: SoakWorkLimiting {
    var inner: CaptureWorkLimiter
    var nextDeadline: TimeInterval? { inner.nextDeadline }
    var isSaturated: Bool { inner.isSaturated }
    var canStart: Bool { inner.canStart }
    mutating func start(at now: TimeInterval) -> Int? { inner.start(at: now) }
    mutating func finish(_ ticket: Int) -> CaptureWorkLimiter.Finish { inner.finish(ticket) }
    mutating func expire(at now: TimeInterval) -> [Int] { [] }
    mutating func abandon(_ ticket: Int) -> Bool { inner.abandon(ticket) }
}
