import XCTest
@testable import TapTheTabCore

final class PreviewFreshnessTests: XCTestCase {
    private typealias Freshness = PreviewFreshness

    func testSharpImageWinsWithoutAThumbnailOrWhenNewer() {
        XCTAssertTrue(Freshness.prefersSharp(sharpCapturedAt: 100, thumbnailCapturedAt: nil))
        XCTAssertTrue(Freshness.prefersSharp(sharpCapturedAt: 100, thumbnailCapturedAt: 90))
        XCTAssertTrue(Freshness.prefersSharp(sharpCapturedAt: 100, thumbnailCapturedAt: 100))
    }

    func testThumbnailBatchFinishingJustAfterTheSharpCaptureKeepsTheSharpImage() {
        // Opening the switcher: the sharp capture goes first, the cards' batch follows.
        let sharp: TimeInterval = 100
        let thumbnail = sharp + Freshness.sharpPreferenceTolerance - 0.5
        XCTAssertTrue(Freshness.prefersSharp(sharpCapturedAt: sharp, thumbnailCapturedAt: thumbnail))
    }

    func testAnOldSharpImageNeverHidesAFreshThumbnail() {
        // The sharp image is from an earlier showing and could not be refreshed since.
        XCTAssertFalse(Freshness.prefersSharp(sharpCapturedAt: 100, thumbnailCapturedAt: 100 + 30 * 60))
        XCTAssertFalse(Freshness.prefersSharp(
            sharpCapturedAt: 100,
            thumbnailCapturedAt: 100 + Freshness.sharpPreferenceTolerance + 0.01
        ))
    }

    func testLateResultsNeverReplaceNewerImages() {
        XCTAssertTrue(Freshness.replaces(10, existing: nil))
        XCTAssertTrue(Freshness.replaces(12, existing: 10))
        XCTAssertTrue(Freshness.replaces(10, existing: 10), "a recapture started at the same moment may replace")
        XCTAssertFalse(Freshness.replaces(9, existing: 10), "a capture started earlier answered later")
    }

    func testFailedRefreshKeepsRecentImagesAndDropsOldOnes() {
        let now: TimeInterval = 5_000
        XCTAssertTrue(Freshness.survivesFailedRefresh(capturedAt: now - 5, now: now), "a hiccup keeps a recent image")
        XCTAssertTrue(Freshness.survivesFailedRefresh(capturedAt: now - Freshness.failedRefreshMaxAge + 0.01, now: now))
        XCTAssertFalse(Freshness.survivesFailedRefresh(capturedAt: now - Freshness.failedRefreshMaxAge, now: now))
        XCTAssertFalse(Freshness.survivesFailedRefresh(capturedAt: now - 30 * 60, now: now), "never frozen for half an hour")
    }

    func testClockGoingBackwardsKeepsTheImage() {
        XCTAssertTrue(Freshness.survivesFailedRefresh(capturedAt: 100, now: 50))
    }

    func testRefreshDelayDoublesPerFailureUpToTheCap() {
        let base = Freshness.refreshInterval
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: 0), base)
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: 1), base * 2)
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: 2), base * 4)
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: 100), Freshness.maxRefreshInterval)
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: Int.max), Freshness.maxRefreshInterval)
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: -3), base)
    }

    func testRefreshDelayCapNeverBelowTheInterval() {
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: 0, interval: 3, maxInterval: 10), 3)
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: 2, interval: 3, maxInterval: 10), 10)
        XCTAssertEqual(Freshness.refreshDelay(afterFailures: 5, interval: 5, maxInterval: 1), 5)
        XCTAssertGreaterThan(Freshness.refreshDelay(afterFailures: 0, interval: 0, maxInterval: 0), 0)
    }
}

final class CaptureWorkLimiterTests: XCTestCase {
    func testRunsAtMostMaxRunningAtOnce() {
        var limiter = CaptureWorkLimiter(maxRunning: 2, maxAbandoned: 2, timeout: 3)
        let first = limiter.start(at: 0)
        let second = limiter.start(at: 0)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
        XCTAssertNil(limiter.start(at: 0))
        XCTAssertFalse(limiter.canStart)
        XCTAssertEqual(limiter.finish(first!), .onTime)
        XCTAssertNotNil(limiter.start(at: 0.1), "an answer frees its slot")
    }

    func testNothingTimesOutBeforeTheDeadline() {
        var limiter = CaptureWorkLimiter(maxRunning: 2, maxAbandoned: 2, timeout: 3)
        _ = limiter.start(at: 10)
        XCTAssertEqual(limiter.nextDeadline, 13)
        XCTAssertEqual(limiter.expire(at: 12.99), [])
        XCTAssertEqual(limiter.runningCount, 1)
    }

    func testAHungCallTimesOutFreesItsSlotAndItsLateAnswerIsIgnored() {
        var limiter = CaptureWorkLimiter(maxRunning: 1, maxAbandoned: 2, timeout: 3)
        let hung = limiter.start(at: 10)!
        XCTAssertNil(limiter.start(at: 11))
        XCTAssertEqual(limiter.expire(at: 13), [hung])
        XCTAssertEqual(limiter.runningCount, 0)
        XCTAssertEqual(limiter.abandonedCount, 1)
        let next = limiter.start(at: 13)
        XCTAssertNotNil(next, "the next capture is not blocked by the hung one")
        XCTAssertEqual(limiter.finish(hung), .late)
        XCTAssertEqual(limiter.abandonedCount, 0)
        XCTAssertEqual(limiter.finish(hung), .unknown, "answers count once")
        XCTAssertEqual(limiter.finish(next!), .onTime)
    }

    func testHungCallsNeverSpawnUnboundedReplacements() {
        var limiter = CaptureWorkLimiter(maxRunning: 4, maxAbandoned: 4, timeout: 3)
        var started = 0
        var mostOutstanding = 0
        var now: TimeInterval = 0
        // Every native call hangs forever; one new request per tick for a minute.
        while now < 60 {
            if limiter.start(at: now) != nil { started += 1 }
            _ = limiter.expire(at: now)
            mostOutstanding = max(mostOutstanding, limiter.runningCount + limiter.abandonedCount)
            now += 0.5
        }
        XCTAssertLessThanOrEqual(mostOutstanding, 4 + 4 - 1)
        XCTAssertEqual(started, mostOutstanding, "every call started is still outstanding")
        XCTAssertTrue(limiter.isSaturated)
        XCTAssertFalse(limiter.canStart)
        XCTAssertNil(limiter.start(at: now))
    }

    func testABurstOfHungCallsSaturatesAtOnce() {
        var limiter = CaptureWorkLimiter(maxRunning: 4, maxAbandoned: 4, timeout: 3)
        for _ in 0..<4 { XCTAssertNotNil(limiter.start(at: 0)) }
        XCTAssertEqual(limiter.expire(at: 3).count, 4)
        XCTAssertTrue(limiter.isSaturated)
        XCTAssertNil(limiter.start(at: 3))
    }

    func testALateAnswerLiftsSaturation() {
        var limiter = CaptureWorkLimiter(maxRunning: 1, maxAbandoned: 1, timeout: 1)
        let hung = limiter.start(at: 0)!
        XCTAssertEqual(limiter.expire(at: 1), [hung])
        XCTAssertTrue(limiter.isSaturated)
        XCTAssertNil(limiter.start(at: 2))
        XCTAssertEqual(limiter.finish(hung), .late)
        XCTAssertFalse(limiter.isSaturated)
        XCTAssertNotNil(limiter.start(at: 2))
    }

    func testExpiresOldestFirstAndOnlyOverdueOnes() {
        var limiter = CaptureWorkLimiter(maxRunning: 4, maxAbandoned: 4, timeout: 3)
        let a = limiter.start(at: 1)!
        let b = limiter.start(at: 0)!
        let c = limiter.start(at: 2.5)!
        XCTAssertEqual(limiter.nextDeadline, 3)
        XCTAssertEqual(limiter.expire(at: 4.2), [b, a])
        XCTAssertEqual(limiter.nextDeadline, 5.5)
        XCTAssertEqual(limiter.finish(c), .onTime)
        XCTAssertNil(limiter.nextDeadline)
    }

    func testAbandonOnlyRunningCalls() {
        var limiter = CaptureWorkLimiter(maxRunning: 1, maxAbandoned: 2, timeout: 3)
        let ticket = limiter.start(at: 0)!
        XCTAssertTrue(limiter.abandon(ticket))
        XCTAssertFalse(limiter.abandon(ticket))
        XCTAssertFalse(limiter.abandon(999))
        XCTAssertEqual(limiter.finish(ticket), .late)
    }

    func testLimitsAreSanitized() {
        let limiter = CaptureWorkLimiter(maxRunning: 0, maxAbandoned: -1, timeout: -5)
        XCTAssertEqual(limiter.maxRunning, 1)
        XCTAssertEqual(limiter.maxAbandoned, 1)
        XCTAssertGreaterThan(limiter.timeout, 0)
        XCTAssertTrue(limiter.canStart)
    }
}

final class LargePreviewRefreshTests: XCTestCase {
    private typealias Schedule = LargePreviewCaptureSchedule

    private func refreshing() -> Schedule {
        Schedule(refreshInterval: 2, maxRefreshInterval: 16)
    }

    func testWithoutAnIntervalNothingRefreshes() {
        var schedule = Schedule()
        XCTAssertNil(schedule.nextRefreshDelay)
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.1, outcome: .captured), .none)
        XCTAssertEqual(schedule.selectionChanged(at: 11), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 11.1, outcome: .failed), .none)
    }

    func testARestingSelectionIsCapturedAgainPeriodically() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.1), .wait(2))
        XCTAssertEqual(schedule.timerFired(at: 12.1), .captureNow)
        XCTAssertTrue(schedule.isCapturing(at: 12.2))
        XCTAssertEqual(schedule.captureFinished(at: 12.2, outcome: .captured), .wait(2))
        XCTAssertEqual(schedule.timerFired(at: 14.2), .captureNow)
    }

    func testFailuresBackOffAndASuccessRestoresTheInterval() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 0), .captureNow)
        var now: TimeInterval = 0
        var waits: [TimeInterval] = []
        for _ in 0..<6 {
            now += 0.1
            guard case .wait(let delay) = schedule.captureFinished(at: now, outcome: .failed) else {
                return XCTFail("a failed refresh must wait before trying again")
            }
            waits.append(delay)
            now += delay
            XCTAssertEqual(schedule.timerFired(at: now), .captureNow)
        }
        XCTAssertEqual(waits, [4, 8, 16, 16, 16, 16])
        XCTAssertEqual(schedule.consecutiveFailures, 6)
        XCTAssertEqual(schedule.captureFinished(at: now + 0.1, outcome: .captured), .wait(2))
        XCTAssertEqual(schedule.consecutiveFailures, 0)
    }

    func testAnotherSelectionForgetsEarlierFailures() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 0), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 0.1, outcome: .failed), .wait(4))
        XCTAssertEqual(schedule.selectionChanged(at: 1), .captureNow)
        XCTAssertEqual(schedule.consecutiveFailures, 0)
        XCTAssertEqual(schedule.captureFinished(at: 1.1, outcome: .failed), .wait(4))
    }

    func testNothingToCaptureStopsRefreshing() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 0), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 0, outcome: .skipped), .none)
        XCTAssertFalse(schedule.isCapturing(at: 0.01))
        // Asking again (the window may be back) captures at once.
        XCTAssertEqual(schedule.timerFired(at: 5), .captureNow)
    }

    func testASelectionChangeDuringACaptureBeatsTheRefresh() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        if case .wait = schedule.selectionChanged(at: 10.5) {} else { XCTFail("queued behind the running capture") }
        XCTAssertEqual(schedule.captureFinished(at: 10.6, outcome: .captured), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.7, outcome: .captured), .wait(2))
    }

    func testRefreshesDoNotMakeTheNextStepCountAsCycling() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.05), .wait(2))
        XCTAssertEqual(schedule.timerFired(at: 12.05), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 12.1), .wait(2))
        // A step long after the last one is a fresh pause, not cycling.
        XCTAssertEqual(schedule.selectionChanged(at: 12.15), .captureNow)
    }

    func testRapidCyclingStillSettlesWithRefreshOn() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.03), .wait(2))
        XCTAssertEqual(schedule.selectionChanged(at: 10.05), .wait(Schedule.settleDelay))
        XCTAssertEqual(schedule.selectionChanged(at: 10.10), .wait(Schedule.settleDelay))
        XCTAssertEqual(schedule.timerFired(at: 10.18), .captureNow)
    }

    func testAHungRefreshStopsBlockingAfterTheTimeout() {
        var schedule = refreshing()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.1), .wait(2))
        XCTAssertEqual(schedule.timerFired(at: 12.1), .captureNow)
        // The refresh never answers; asking again after the timeout captures again.
        XCTAssertEqual(schedule.timerFired(at: 12.1 + Schedule.captureTimeout + 0.01), .captureNow)
    }

    func testOldCaptureCompletionPreservesTheCyclingSettleTimer() {
        for outcome in [Schedule.Outcome.captured, .failed] {
            var schedule = refreshing()
            XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
            XCTAssertEqual(schedule.selectionChanged(at: 10.05), .wait(Schedule.settleDelay))
            XCTAssertEqual(schedule.selectionChanged(at: 10.10), .wait(Schedule.settleDelay))
            XCTAssertEqual(schedule.captureFinished(at: 10.14, outcome: outcome), .none,
                           "the existing settle timer must not become a two-second refresh")
            XCTAssertEqual(schedule.timerFired(at: 10.18), .captureNow)
            XCTAssertEqual(schedule.captureFinished(at: 10.20), .wait(2))
        }
    }

    func testOnlyASkippedCapturePermitsAnInputRetry() {
        var schedule = refreshing()
        XCTAssertFalse(schedule.needsCaptureRetry)
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertFalse(schedule.isCapturing(at: 12), "the schedule timeout elapsed")
        XCTAssertFalse(schedule.needsCaptureRetry, "a slow outstanding capture is not skipped")
        XCTAssertEqual(schedule.captureFinished(at: 13, outcome: .failed), .wait(4))
        XCTAssertFalse(schedule.needsCaptureRetry, "failures keep their backoff")
        XCTAssertEqual(schedule.timerFired(at: 17), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 17.1, outcome: .skipped), .none)
        XCTAssertTrue(schedule.needsCaptureRetry, "restore/unhide can now retry")
        XCTAssertEqual(schedule.timerFired(at: 18), .captureNow)
        XCTAssertFalse(schedule.needsCaptureRetry)
    }

    func testRefreshIntervalIsSanitized() {
        let schedule = Schedule(refreshInterval: 0, maxRefreshInterval: -1)
        XCTAssertNotNil(schedule.nextRefreshDelay)
        XCTAssertGreaterThan(schedule.nextRefreshDelay ?? 0, 0)
        XCTAssertGreaterThanOrEqual(schedule.maxRefreshInterval, schedule.refreshInterval ?? 0)
    }
}

final class PreviewCaptureTargetOwnerTests: XCTestCase {
    func testAReusedWindowNumberIsCapturedAgain() {
        let before = PreviewCaptureTarget(id: .window(7), pixelSize: 1200, owner: 100)
        let reused = PreviewCaptureTarget(id: .window(7), pixelSize: 1200, owner: 200)
        XCTAssertTrue(reused.requiresCapture(after: before))
    }

    func testSameOwnerOrUnknownOwnerKeepsTheOldRules() {
        let first = PreviewCaptureTarget(id: .window(7), pixelSize: 1200, owner: 100)
        XCTAssertFalse(PreviewCaptureTarget(id: .window(7), pixelSize: 1200, owner: 100).requiresCapture(after: first))
        XCTAssertFalse(PreviewCaptureTarget(id: .window(7), pixelSize: 1200).requiresCapture(after: first))
        XCTAssertFalse(first.requiresCapture(after: PreviewCaptureTarget(id: .window(7), pixelSize: 1200)))
        XCTAssertTrue(PreviewCaptureTarget(id: .window(7), pixelSize: 1600, owner: 100).requiresCapture(after: first))
    }
}
