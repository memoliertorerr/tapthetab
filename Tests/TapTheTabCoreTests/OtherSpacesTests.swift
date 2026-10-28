import XCTest
@testable import TapTheTabCore

final class OtherSpacesTests: XCTestCase {
    // MARK: - SpaceLayout

    func testParsesDisplaysSpacesAndCurrentSpace() {
        let displays: [[String: Any]] = [
            [
                "Display Identifier": "Main",
                "Current Space": ["id64": 3, "type": 0],
                "Spaces": [
                    ["id64": 1, "type": 0],
                    ["id64": 3, "type": 0],
                    ["id64": 7, "type": 4],
                ],
            ],
            [
                "Display Identifier": "2B6E-…",
                "Current Space": ["ManagedSpaceID": 9],
                "Spaces": [["ManagedSpaceID": 9, "type": 0], ["ManagedSpaceID": 10]],
            ],
        ]
        XCTAssertEqual(SpaceLayout.spaces(fromManagedDisplaySpaces: displays), [
            SpaceInfo(id: 1),
            SpaceInfo(id: 3, isCurrent: true),
            SpaceInfo(id: 7, isFullscreen: true),
            SpaceInfo(id: 9, isCurrent: true),
            SpaceInfo(id: 10),
        ])
    }

    func testParsesNSNumbers() {
        let displays: [[String: Any]] = [[
            "Current Space": ["id64": NSNumber(value: 5)],
            "Spaces": [["id64": NSNumber(value: 5), "type": NSNumber(value: 0)], ["id64": NSNumber(value: 6), "type": NSNumber(value: 4)]],
        ]]
        XCTAssertEqual(SpaceLayout.spaces(fromManagedDisplaySpaces: displays), [
            SpaceInfo(id: 5, isCurrent: true),
            SpaceInfo(id: 6, isFullscreen: true),
        ])
    }

    func testMalformedInputIsSkippedNotFatal() {
        let displays: [[String: Any]] = [
            [:],
            ["Spaces": "nope"],
            ["Spaces": [1, "x", ["type": 0], ["id64": "4"], ["id64": 0], ["id64": -2]]],
            ["Spaces": [["id64": 8, "type": 2]]],  // system Space type: skipped
            ["Spaces": [["id64": 11, "type": 0], ["id64": 11, "type": 0]]],  // listed twice
            ["Current Space": "x", "Spaces": [["id64": 12]]],
        ]
        XCTAssertEqual(SpaceLayout.spaces(fromManagedDisplaySpaces: displays), [SpaceInfo(id: 11), SpaceInfo(id: 12)])
        XCTAssertEqual(SpaceLayout.spaces(fromManagedDisplaySpaces: []), [])
    }

    // MARK: - Candidates

    func testCandidatesSkipCurrentSpacesKnownWindowsAndDuplicates() {
        let spaces = [
            SpaceInfo(id: 1, isCurrent: true),
            SpaceInfo(id: 2),
            SpaceInfo(id: 3, isFullscreen: true),
            SpaceInfo(id: 4),
        ]
        let ids: [[UInt32]] = [
            [10, 11, 99],       // current Space; 99 is on every Space
            [20, 99, 21, 0],    // 0 is never a window
            [30, 20],           // 20 already listed for Space 2
            [40],
        ]
        let result = OtherSpaceWindows.candidates(spaces: spaces, windowIDsBySpace: ids, excluding: [21, 40])
        XCTAssertEqual(result, [
            SpaceWindowCandidate(windowID: 20, spaceIndex: 1),
            SpaceWindowCandidate(windowID: 30, spaceIndex: 2, isFullscreenSpace: true),
        ])
    }

    func testCandidatesWithFewerListsThanSpaces() {
        // The time budget ran out after the second Space.
        let spaces = [SpaceInfo(id: 1), SpaceInfo(id: 2), SpaceInfo(id: 3)]
        let result = OtherSpaceWindows.candidates(spaces: spaces, windowIDsBySpace: [[5], [6]], excluding: [])
        XCTAssertEqual(result.map(\.windowID), [5, 6])
        XCTAssertEqual(OtherSpaceWindows.candidates(spaces: spaces, windowIDsBySpace: [], excluding: []), [])
    }

    // MARK: - Selection

    private func described(_ id: UInt32, pid: Int32, layer: Int = 0, alpha: Double = 1, width: Double = 800, height: Double = 600) -> WindowServerWindow {
        WindowServerWindow(id: id, pid: pid, layer: layer, alpha: alpha, width: width, height: height)
    }

    func testSwitchableNeedsNormalLayerVisibleAndMinimumSize() {
        XCTAssertTrue(OtherSpaceWindows.isSwitchable(described(1, pid: 1)))
        XCTAssertTrue(OtherSpaceWindows.isSwitchable(described(1, pid: 1, width: 50, height: 50)))
        XCTAssertFalse(OtherSpaceWindows.isSwitchable(described(1, pid: 1, layer: 3)))
        XCTAssertFalse(OtherSpaceWindows.isSwitchable(described(1, pid: 1, layer: -1)))
        XCTAssertFalse(OtherSpaceWindows.isSwitchable(described(1, pid: 1, alpha: 0)))
        XCTAssertFalse(OtherSpaceWindows.isSwitchable(described(1, pid: 1, width: 49.9)))
        XCTAssertFalse(OtherSpaceWindows.isSwitchable(described(1, pid: 1, height: 20)))
    }

    func testSelectFiltersAndOrdersByAppThenSpaceThenFrontToBack() {
        let candidates = [
            SpaceWindowCandidate(windowID: 1, spaceIndex: 1),
            SpaceWindowCandidate(windowID: 2, spaceIndex: 1),
            SpaceWindowCandidate(windowID: 3, spaceIndex: 1),
            SpaceWindowCandidate(windowID: 4, spaceIndex: 2, isFullscreenSpace: true),
            SpaceWindowCandidate(windowID: 5, spaceIndex: 2),
            SpaceWindowCandidate(windowID: 6, spaceIndex: 3),
            SpaceWindowCandidate(windowID: 7, spaceIndex: 3),
            SpaceWindowCandidate(windowID: 8, spaceIndex: 3),
        ]
        let descriptions: [UInt32: WindowServerWindow] = [
            1: described(1, pid: 200),
            2: described(2, pid: 100),
            3: described(3, pid: 100, layer: 25),     // status-bar layer
            4: described(4, pid: 100),
            5: described(5, pid: 300),                // not a listed app (agent, our own)
            6: described(6, pid: 200, alpha: 0),
            7: described(7, pid: 100),
            // 8 has no description (closed meanwhile)
        ]
        let appOrder: [Int32: Int] = [100: 0, 200: 1]
        let result = OtherSpaceWindows.select(candidates, descriptions: descriptions, appOrder: appOrder)
        XCTAssertEqual(result.map(\.windowID), [2, 4, 7, 1])
        XCTAssertEqual(result.map(\.isFullscreenSpace), [false, true, false, false])
    }

    func testSelectEmpty() {
        XCTAssertEqual(OtherSpaceWindows.select([], descriptions: [:], appOrder: [:]), [])
        let one = [SpaceWindowCandidate(windowID: 1, spaceIndex: 0)]
        XCTAssertEqual(OtherSpaceWindows.select(one, descriptions: [1: described(1, pid: 1)], appOrder: [:]), [])
    }

    // MARK: - Titles

    func testTitlePrefersAccessibilityThenPreviousThenWindowServer() {
        XCTAssertEqual(OtherSpaceWindows.title(accessibility: "AX", previous: "Old", windowServer: "WS"), "AX")
        XCTAssertEqual(OtherSpaceWindows.title(accessibility: nil, previous: "Old", windowServer: "WS"), "Old")
        XCTAssertEqual(OtherSpaceWindows.title(accessibility: "  ", previous: "", windowServer: "WS"), "WS")
        XCTAssertEqual(OtherSpaceWindows.title(accessibility: nil, previous: nil, windowServer: nil), "")
    }

    func testUntitledWindowShowsAppName() {
        let title = OtherSpaceWindows.title(accessibility: nil, previous: nil, windowServer: nil)
        let item = SwitcherItem(id: .window(1), pid: 1, appName: "Notes", title: title, isOnActiveSpace: false)
        XCTAssertEqual(item.displayTitle, "Notes")
    }
}
