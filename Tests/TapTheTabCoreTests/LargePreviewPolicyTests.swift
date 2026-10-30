import XCTest
@testable import TapTheTabCore

final class LargePreviewCaptureScheduleTests: XCTestCase {
    private typealias Schedule = LargePreviewCaptureSchedule

    private func assertWait(_ decision: Schedule.Decision, seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        guard case .wait(let actual) = decision else {
            XCTFail("Expected a wait, got \(decision)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, seconds, accuracy: 1e-9, file: file, line: line)
    }

    func testFinalSelectionRetriesWithoutMoreInputAfterATimeout() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        assertWait(schedule.selectionChanged(at: 10.5), seconds: 0.5)
        XCTAssertEqual(schedule.timerFired(at: 11), .captureNow)
    }

    func testFirstSelectionCapturesAtOnce() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertTrue(schedule.isCapturing(at: 10.01))
    }

    func testSlowStepsCaptureAtOnceWithoutADelay() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.05), .none)
        XCTAssertEqual(schedule.selectionChanged(at: 10.5), .captureNow)
    }

    func testCyclingWaitsForTheSelectionToRest() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.04), .none)
        XCTAssertEqual(schedule.selectionChanged(at: 10.05), .wait(Schedule.settleDelay))
        XCTAssertEqual(schedule.selectionChanged(at: 10.10), .wait(Schedule.settleDelay))
        XCTAssertFalse(schedule.isCapturing(at: 10.11), "nothing starts while cycling")
        XCTAssertEqual(schedule.timerFired(at: 10.18), .captureNow)
    }

    func testOnlyOneCaptureRunsAtATime() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        // A slow step while the first capture still runs: queued, not started alongside.
        assertWait(schedule.selectionChanged(at: 10.2), seconds: 0.8)
        assertWait(schedule.selectionChanged(at: 10.4), seconds: 0.6)
        // One follow-up capture for the latest selection, however many steps were queued.
        XCTAssertEqual(schedule.captureFinished(at: 10.5), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.6), .none)
    }

    func testTimerDuringACaptureQueuesOneFollowUp() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.selectionChanged(at: 10.05), .wait(Schedule.settleDelay))
        assertWait(schedule.timerFired(at: 10.13), seconds: 0.87)
        XCTAssertEqual(schedule.captureFinished(at: 10.2), .captureNow)
    }

    func testCyclingCancelsAQueuedFollowUp() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        assertWait(schedule.selectionChanged(at: 10.2), seconds: 0.8)
        // Cycling now: the settle timer owns the next capture, so the finished capture
        // must not start another one as well.
        XCTAssertEqual(schedule.selectionChanged(at: 10.25), .wait(Schedule.settleDelay))
        XCTAssertEqual(schedule.captureFinished(at: 10.28), .none)
        XCTAssertEqual(schedule.timerFired(at: 10.33), .captureNow)
    }

    func testAStuckCaptureStopsBlockingAfterTheTimeout() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        assertWait(schedule.selectionChanged(at: 10.5), seconds: 0.5)
        XCTAssertEqual(schedule.selectionChanged(at: 10 + Schedule.captureTimeout + 0.2), .captureNow)
    }

    func testClockGoingBackwardsIsNotCycling() {
        var schedule = Schedule()
        XCTAssertEqual(schedule.selectionChanged(at: 10), .captureNow)
        XCTAssertEqual(schedule.captureFinished(at: 10.01), .none)
        XCTAssertEqual(schedule.selectionChanged(at: 9.95), .captureNow)
    }

    func testFreshScheduleForgetsTheLastSession() {
        var schedule = Schedule()
        _ = schedule.selectionChanged(at: 10)
        schedule = Schedule()
        XCTAssertFalse(schedule.isCapturing(at: 10.01))
        XCTAssertEqual(schedule.selectionChanged(at: 10.02), .captureNow)
    }
}

final class PreviewImageRetentionTests: XCTestCase {
    func testKeepsAtMostMaxCountMostRecent() {
        var retention = PreviewImageRetention<Int>(maxCount: 3, maxPixels: .max)
        XCTAssertEqual(retention.insert(1, pixels: 10), [])
        XCTAssertEqual(retention.insert(2, pixels: 10), [])
        XCTAssertEqual(retention.insert(3, pixels: 10), [])
        XCTAssertEqual(retention.insert(4, pixels: 10), [1])
        XCTAssertEqual(retention.keys, [2, 3, 4])
    }

    func testPixelBudgetDropsTheOldest() {
        var retention = PreviewImageRetention<Int>(maxCount: 10, maxPixels: 100)
        _ = retention.insert(1, pixels: 40)
        _ = retention.insert(2, pixels: 40)
        XCTAssertEqual(retention.insert(3, pixels: 40), [1])
        XCTAssertEqual(retention.totalPixels, 80)
    }

    func testNewestIsKeptEvenWhenItAloneExceedsTheBudget() {
        var retention = PreviewImageRetention<Int>(maxCount: 3, maxPixels: 100)
        _ = retention.insert(1, pixels: 50)
        XCTAssertEqual(retention.insert(2, pixels: 500), [1])
        XCTAssertEqual(retention.keys, [2])
    }

    func testProtectedKeySurvivesNewerArrivals() {
        var retention = PreviewImageRetention<Int>(maxCount: 2, maxPixels: .max)
        _ = retention.insert(1, pixels: 10)
        // Late results for other windows arrive while 1 is selected.
        XCTAssertEqual(retention.insert(2, pixels: 10, protecting: 1), [])
        XCTAssertEqual(retention.insert(3, pixels: 10, protecting: 1), [2])
        XCTAssertEqual(Set(retention.keys), [1, 3])
    }

    func testProtectedAndNewestBothKeptOverBudget() {
        var retention = PreviewImageRetention<Int>(maxCount: 1, maxPixels: .max)
        _ = retention.insert(1, pixels: 10)
        XCTAssertEqual(retention.insert(2, pixels: 10, protecting: 1), [])
        XCTAssertEqual(Set(retention.keys), [1, 2], "never drops the shown image")
        XCTAssertEqual(retention.insert(3, pixels: 10, protecting: 3), [1, 2])
    }

    func testReplacingAKeyDoesNotDoubleCountIt() {
        var retention = PreviewImageRetention<Int>(maxCount: 3, maxPixels: 100)
        _ = retention.insert(1, pixels: 60)
        XCTAssertEqual(retention.insert(1, pixels: 70), [])
        XCTAssertEqual(retention.totalPixels, 70)
        XCTAssertEqual(retention.keys, [1])
    }

    func testTouchMakesAKeyMostRecent() {
        var retention = PreviewImageRetention<Int>(maxCount: 2, maxPixels: .max)
        _ = retention.insert(1, pixels: 10)
        _ = retention.insert(2, pixels: 10)
        retention.touch(1)
        XCTAssertEqual(retention.insert(3, pixels: 10), [2])
        retention.touch(99)
        XCTAssertFalse(retention.contains(99))
    }

    func testPruneAndRemove() {
        var retention = PreviewImageRetention<Int>(maxCount: 5, maxPixels: .max)
        for key in 1...4 { _ = retention.insert(key, pixels: 10) }
        XCTAssertEqual(retention.prune(keeping: [2, 4, 7]), [1, 3])
        XCTAssertEqual(retention.keys, [2, 4])
        XCTAssertEqual(retention.prune(keeping: [2, 4]), [])
        retention.remove(2)
        XCTAssertEqual(retention.keys, [4])
        XCTAssertEqual(retention.totalPixels, 10)
        retention.removeAll()
        XCTAssertTrue(retention.keys.isEmpty)
        XCTAssertEqual(retention.totalPixels, 0)
    }

    func testLimitsAreSanitized() {
        let retention = PreviewImageRetention<Int>(maxCount: 0, maxPixels: -5)
        XCTAssertEqual(retention.maxCount, 1)
        XCTAssertEqual(retention.maxPixels, 0)
    }
}

final class PreviewSelectionAnimationTests: XCTestCase {
    func testFirstStepAnimatesWhenEnabled() {
        XCTAssertTrue(PreviewSelectionAnimation.shouldAnimate(enabled: true, previousChange: nil, now: 10))
    }

    func testRapidStepsSnapAndMotionResumesAfterPause() {
        XCTAssertFalse(PreviewSelectionAnimation.shouldAnimate(enabled: true, previousChange: 10, now: 10.03))
        XCTAssertFalse(PreviewSelectionAnimation.shouldAnimate(enabled: true, previousChange: 10.03, now: 10.06))
        XCTAssertTrue(PreviewSelectionAnimation.shouldAnimate(enabled: true, previousChange: 10.06, now: 10.5))
    }

    func testDisabledAndReducedMotionNeverAnimate() {
        XCTAssertFalse(PreviewSelectionAnimation.shouldAnimate(enabled: false, previousChange: nil, now: 10))
        XCTAssertFalse(PreviewSelectionAnimation.shouldAnimate(enabled: false, previousChange: 10, now: 11))
    }

    func testBackwardsTimeDoesNotStartAnotherAnimation() {
        XCTAssertFalse(PreviewSelectionAnimation.shouldAnimate(enabled: true, previousChange: 10, now: 9))
    }
}

final class PreviewCaptureTargetTests: XCTestCase {
    func testRecapturesWhenFilteringEnlargesTheSameWindowPreview() {
        let small = PreviewCaptureTarget(id: .window(1), pixelSize: 600)
        let large = PreviewCaptureTarget(id: .window(1), pixelSize: 1200)
        XCTAssertTrue(small.requiresCapture(after: nil))
        XCTAssertTrue(large.requiresCapture(after: small))
        XCTAssertFalse(large.requiresCapture(after: large))
        XCTAssertFalse(small.requiresCapture(after: large))
    }

    func testChangingWindowsCapturesEvenAtTheSameResolution() {
        let first = PreviewCaptureTarget(id: .window(1), pixelSize: 1200)
        let next = PreviewCaptureTarget(id: .window(2), pixelSize: 1200)
        XCTAssertTrue(next.requiresCapture(after: first))
    }
}
