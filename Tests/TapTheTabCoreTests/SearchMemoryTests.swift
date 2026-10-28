import XCTest
@testable import TapTheTabCore

final class SearchMemoryTests: XCTestCase {
    private let slack = window(10, pid: 2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "general")
    private let slackOther = window(11, pid: 2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "random")
    private let safari = window(20, pid: 3, app: "Safari", bundle: "com.apple.Safari", title: "Apple")

    // MARK: - Empty / basics

    func testNewMemoryIsEmptyAndBoostsNothing() {
        let memory = SearchMemory()
        XCTAssertTrue(memory.isEmpty)
        XCTAssertEqual(memory.count, 0)
        XCTAssertEqual(memory.capacity, 256)
        XCTAssertEqual(memory.boost(query: "sl", for: slack), 0)
    }

    func testRecordMakesItNonEmpty() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        XCTAssertFalse(memory.isEmpty)
        XCTAssertEqual(memory.count, 1)
    }

    func testEmptyOrWhitespaceQueryIsNotRecorded() {
        var memory = SearchMemory()
        memory.record(query: "", picked: slack)
        memory.record(query: "  \t ", picked: slack)
        XCTAssertTrue(memory.isEmpty)
    }

    func testEmptyQueryNeverBoosts() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        XCTAssertEqual(memory.boost(query: "", for: slack), 0)
        XCTAssertEqual(memory.boost(query: "   ", for: slack), 0)
    }

    func testUnrelatedQueryDoesNotBoost() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        XCTAssertEqual(memory.boost(query: "ma", for: slack), 0)
        XCTAssertEqual(memory.boost(query: "ls", for: slack), 0)
    }

    func testOtherAppsAreNotBoosted() {
        var memory = SearchMemory()
        memory.record(query: "s", picked: slack)
        XCTAssertEqual(memory.boost(query: "s", for: safari), 0)
    }

    // MARK: - Exact numbers (documented rules)

    func testSinglePickExactQueryBoost() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        // window tier 30 (base 30 × 100 % × 100 %) + app tier 30 / 2.
        XCTAssertEqual(memory.boost(query: "sl", for: slack), 45)
        // Another window of the same app: app tier only.
        XCTAssertEqual(memory.boost(query: "sl", for: slackOther), 15)
    }

    func testPrefixRelationWeights() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        // "s" vs "sl": relation 50 + 50 × 1/2 = 75 % → window 22, app 22 / 2 = 11.
        XCTAssertEqual(memory.boost(query: "s", for: slack), 22 + 11)
        // "slac" vs "sl": 50 + 50 × 2/4 = 75 % as well.
        XCTAssertEqual(memory.boost(query: "slac", for: slack), 22 + 11)
        // "slack" vs "sl": 50 + 50 × 2/5 = 70 % → window 21, app 10.
        XCTAssertEqual(memory.boost(query: "slack", for: slack), 21 + 10)
    }

    func testRelationPercent() {
        XCTAssertEqual(SearchMemory.relationPercent(current: "sl", remembered: "sl"), 100)
        XCTAssertEqual(SearchMemory.relationPercent(current: "s", remembered: "sl"), 75)
        XCTAssertEqual(SearchMemory.relationPercent(current: "slac", remembered: "sl"), 75)
        XCTAssertNil(SearchMemory.relationPercent(current: "sa", remembered: "sl"))
    }

    func testTypingLessAndTypingMoreBothHelp() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        XCTAssertGreaterThan(memory.boost(query: "s", for: slack), 0)
        XCTAssertGreaterThan(memory.boost(query: "slac", for: slack), 0)
        XCTAssertGreaterThan(memory.boost(query: "sl", for: slack), memory.boost(query: "s", for: slack),
                             "the exact query counts most")
    }

    // MARK: - Normalisation

    func testQueriesAreFoldedTrimmedAndCollapsed() {
        var memory = SearchMemory()
        memory.record(query: "  Café   Menu ", picked: slack)
        XCTAssertEqual(memory.boost(query: "cafe menu", for: slack), 45)
        XCTAssertEqual(memory.boost(query: "CAFÉ\tMENU", for: slack), 45)
        memory.record(query: "cafe menu", picked: slack)
        XCTAssertEqual(memory.count, 1, "both spellings are the same remembered query")
    }

    func testNormalize() {
        XCTAssertEqual(SearchMemory.normalize("  Ünïcödé   ＡＢ \n x "), "unicode ab x")
        XCTAssertEqual(SearchMemory.normalize(" \t "), "")
    }

    // MARK: - Identity

    func testAppIdentitySurvivesWindowChange() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        let newWindow = window(99, pid: 77, app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "new")
        XCTAssertEqual(memory.boost(query: "sl", for: newWindow), 15, "relaunched app, new window and pid")
    }

    func testBundleIDComparisonIsCaseInsensitive() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        let shouty = window(12, app: "Slack", bundle: "COM.TINYSPECK.SLACKMACGAP")
        XCTAssertEqual(memory.boost(query: "sl", for: shouty), 15)
    }

    func testAppNameIsUsedWithoutBundleID() {
        var memory = SearchMemory()
        let noBundle = window(1, app: "Tool")
        memory.record(query: "to", picked: noBundle)
        XCTAssertEqual(memory.boost(query: "to", for: window(2, app: "tool")), 15)
        XCTAssertEqual(memory.boost(query: "to", for: window(3, app: "Tools")), 0)
    }

    func testReusedWindowNumberFromAnotherAppGetsNoWindowBoost() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        let impostor = window(10, pid: 5, app: "Sleeper", bundle: "com.example.sleeper")
        XCTAssertEqual(memory.boost(query: "sl", for: impostor), 0)
    }

    func testWindowlessAppEntryIsRemembered() {
        var memory = SearchMemory()
        let calc = windowlessApp(pid: 7, app: "Calculator", bundle: "com.apple.calculator")
        memory.record(query: "calc", picked: calc)
        XCTAssertEqual(memory.boost(query: "calc", for: calc), 45)
        let calcWindow = window(5, pid: 7, app: "Calculator", bundle: "com.apple.calculator")
        XCTAssertEqual(memory.boost(query: "calc", for: calcWindow), 15)
    }

    func testExactWindowBeatsSameAppWithSameHistory() {
        var memory = SearchMemory()
        memory.record(query: "s", picked: slack)
        memory.record(query: "s", picked: slackOther)
        memory.record(query: "s", picked: slack)
        XCTAssertGreaterThan(memory.boost(query: "s", for: slack), memory.boost(query: "s", for: slackOther))
    }

    // MARK: - Frequency and recency

    func testFrequencyIncreasesBoostAndSaturates() {
        var memory = SearchMemory()
        var boosts: [Int] = []
        for _ in 0..<8 {
            memory.record(query: "sl", picked: slack)
            boosts.append(memory.boost(query: "sl", for: slack))
        }
        // base 30, 36, 42, 48, 54, 60, 60, 60 (+ half for the app tier).
        XCTAssertEqual(boosts, [45, 54, 63, 72, 81, 90, 90, 90])
        XCTAssertEqual(boosts.max(), SearchMemory.maximumBoost)
        XCTAssertEqual(memory.count, 1)
    }

    func testRecencyDecaysWithLaterPicksAndHasAFloor() {
        var memory = SearchMemory()
        memory.record(query: "sl", picked: slack)
        memory.record(query: "sa", picked: safari)
        // Age 1 → 98 %: 30 × 98 % = 29, app tier 14.
        XCTAssertEqual(memory.boost(query: "sl", for: slack), 29 + 14)
        for _ in 0..<100 { memory.record(query: "sa", picked: safari) }
        // Floor 30 %: 30 × 30 % = 9, app tier 4.
        XCTAssertEqual(memory.boost(query: "sl", for: slack), 9 + 4)
    }

    func testMoreRecentPickWinsOverOlderSinglePick() {
        var memory = SearchMemory()
        memory.record(query: "s", picked: safari)
        memory.record(query: "s", picked: slack)
        XCTAssertGreaterThan(memory.boost(query: "s", for: slack), memory.boost(query: "s", for: safari))
    }

    func testMoreFrequentPickWinsOverOneRecentPick() {
        var memory = SearchMemory()
        for _ in 0..<5 { memory.record(query: "s", picked: safari) }
        memory.record(query: "s", picked: slack)
        XCTAssertGreaterThan(memory.boost(query: "s", for: safari), memory.boost(query: "s", for: slack))
    }

    func testBestEntryWinsAcrossRelatedQueries() {
        var memory = SearchMemory()
        memory.record(query: "s", picked: slack)
        memory.record(query: "sl", picked: slack)
        // For "sl": the exact "sl" entry (30) beats "s" (75 % at age 1 → 22).
        XCTAssertEqual(memory.boost(query: "sl", for: slack), 45)
        XCTAssertEqual(memory.count, 2)
    }

    func testBoostNeverExceedsMaximum() {
        var memory = SearchMemory()
        for q in ["s", "sl", "sla", "slac", "slack"] {
            for _ in 0..<10 { memory.record(query: q, picked: slack) }
        }
        for q in ["s", "sl", "sla", "slac", "slack", "slack general"] {
            XCTAssertLessThanOrEqual(memory.boost(query: q, for: slack), SearchMemory.maximumBoost, q)
        }
        XCTAssertEqual(SearchMemory.maximumBoost, 90)
    }

    // MARK: - Capacity

    func testEvictsLeastRecentlyUsedBeyondCapacity() {
        var memory = SearchMemory(capacity: 2)
        memory.record(query: "a", picked: window(1, app: "A1"))
        memory.record(query: "b", picked: window(2, app: "B1"))
        memory.record(query: "a", picked: window(1, app: "A1")) // refresh "a"
        memory.record(query: "c", picked: window(3, app: "C1"))
        XCTAssertEqual(memory.count, 2)
        XCTAssertGreaterThan(memory.boost(query: "a", for: window(1, app: "A1")), 0)
        XCTAssertEqual(memory.boost(query: "b", for: window(2, app: "B1")), 0, "least recently used is gone")
        XCTAssertGreaterThan(memory.boost(query: "c", for: window(3, app: "C1")), 0)
    }

    func testDefaultCapacityBoundsSize() {
        var memory = SearchMemory()
        for n in 0..<300 {
            memory.record(query: "q\(n)", picked: window(UInt32(n)))
        }
        XCTAssertEqual(memory.count, 256)
    }

    func testZeroOrNegativeCapacityDisablesMemory() {
        var zero = SearchMemory(capacity: 0)
        zero.record(query: "sl", picked: slack)
        XCTAssertTrue(zero.isEmpty)
        XCTAssertEqual(zero.boost(query: "sl", for: slack), 0)
        XCTAssertEqual(SearchMemory(capacity: -5).capacity, 0)
    }

    // MARK: - Determinism

    func testSameHistoryGivesEqualMemories() {
        func build() -> SearchMemory {
            var m = SearchMemory()
            m.record(query: "sl", picked: slack)
            m.record(query: "sa", picked: safari)
            m.record(query: "sl", picked: slack)
            return m
        }
        XCTAssertEqual(build(), build())
        XCTAssertNotEqual(build(), SearchMemory())
    }

    func testScorerMatchesBoost() {
        var memory = SearchMemory()
        memory.record(query: "s", picked: slack)
        memory.record(query: "sa", picked: safari)
        let scorer = memory.scorer(for: "s")
        for item in [slack, slackOther, safari, window(1, app: "Other")] {
            XCTAssertEqual(scorer(item), memory.boost(query: "s", for: item))
        }
    }
}
