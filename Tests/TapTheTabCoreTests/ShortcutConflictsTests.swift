import XCTest
@testable import TapTheTabCore

final class ShortcutConflictsTests: XCTestCase {
    private func shortcut(_ string: String) -> Shortcut {
        guard let parsed = Shortcut(string: string) else {
            XCTFail("bad shortcut \(string)")
            return .optionTab
        }
        return parsed
    }

    private func trigger(_ string: String, _ scope: SwitcherScope = .allWindows) -> Trigger {
        Trigger(shortcut: shortcut(string), scope: scope)
    }

    // MARK: - System features

    func testKnownSystemShortcuts() {
        let expected: [(String, String)] = [
            ("cmd+space", "Spotlight"),
            ("ctrl+space", "Input Sources"),
            ("shift+cmd+3", "Screenshot"),
            ("shift+cmd+4", "Screenshot of a Selection"),
            ("shift+cmd+5", "Screenshot Toolbar"),
            ("cmd+q", "Quit App"),
            ("cmd+w", "Close Window"),
            ("cmd+h", "Hide App"),
            ("cmd+m", "Minimize Window"),
            ("cmd+`", "Cycle App Windows"),
        ]
        for (string, feature) in expected {
            XCTAssertEqual(ShortcutConflicts.systemFeature(for: shortcut(string)), feature, string)
        }
        XCTAssertEqual(ShortcutConflicts.known.count, expected.count, "every entry is covered above")
    }

    func testKnownListHasNoDuplicates() {
        XCTAssertEqual(Set(ShortcutConflicts.known.map(\.shortcut)).count, ShortcutConflicts.known.count)
        XCTAssertEqual(Set(ShortcutConflicts.known.map(\.feature)).count, ShortcutConflicts.known.count)
    }

    func testDefaultsAndPresetsAreFree() {
        for s in ["option+tab", "option+`", "ctrl+tab", "ctrl+`", "cmd+tab", "option+space"] {
            XCTAssertNil(ShortcutConflicts.systemFeature(for: shortcut(s)), s)
        }
    }

    func testModifiersMustMatchExactly() {
        XCTAssertNil(ShortcutConflicts.systemFeature(for: shortcut("cmd+3")))
        XCTAssertNil(ShortcutConflicts.systemFeature(for: shortcut("shift+cmd+space")))
        XCTAssertNil(ShortcutConflicts.systemFeature(for: shortcut("option+cmd+space")))
        XCTAssertNil(ShortcutConflicts.systemFeature(for: shortcut("shift+cmd+q")))
        XCTAssertNil(ShortcutConflicts.systemFeature(for: shortcut("space")))
    }

    func testFnIsIgnored() {
        XCTAssertEqual(ShortcutConflicts.systemFeature(for: shortcut("fn+cmd+space")), "Spotlight")
    }

    func testCommandGraveIsReportedUntilItIsOwnTrigger() {
        XCTAssertEqual(ShortcutConflicts.systemFeature(for: .commandGrave), "Cycle App Windows")
        XCTAssertEqual(ShortcutConflicts.systemFeature(for: .commandGrave, ownTriggers: Configuration.defaultTriggers),
                       "Cycle App Windows")
        let own = [Trigger(shortcut: .commandGrave, scope: .activeApp)]
        XCTAssertNil(ShortcutConflicts.systemFeature(for: .commandGrave, ownTriggers: own))
        XCTAssertNil(ShortcutConflicts.systemFeature(for: .commandGrave, ownTriggers: [trigger("fn+cmd+`")]))
    }

    func testOwnTriggersDoNotHideRealCollisions() {
        let own = [trigger("cmd+space")]
        XCTAssertEqual(ShortcutConflicts.systemFeature(for: shortcut("cmd+space"), ownTriggers: own), "Spotlight")
    }

    func testIsTakenOver() {
        XCTAssertTrue(ShortcutConflicts.isTakenOver(.commandGrave))
        XCTAssertTrue(ShortcutConflicts.isTakenOver(shortcut("fn+cmd+`")))
        XCTAssertFalse(ShortcutConflicts.isTakenOver(shortcut("cmd+space")))
        XCTAssertFalse(ShortcutConflicts.isTakenOver(.optionGrave))
    }

    // MARK: - ⇧ reverse conflicts

    func testShiftedVersionOfExistingTriggerConflicts() {
        let triggers = [trigger("option+tab")]
        XCTAssertEqual(ShortcutConflicts.reverseConflict(for: shortcut("shift+option+tab"), among: triggers), triggers[0])
    }

    func testUnshiftedVersionOfExistingTriggerConflicts() {
        let triggers = [trigger("shift+option+tab")]
        XCTAssertEqual(ShortcutConflicts.reverseConflict(for: .optionTab, among: triggers), triggers[0])
    }

    func testSameShortcutIsNotAReverseConflict() {
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: .optionTab, among: [trigger("option+tab")]))
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: .optionTab, among: [trigger("fn+option+tab")]))
    }

    func testDifferentKeyOrModifiersDoNotConflict() {
        let triggers = Configuration.defaultTriggers
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: shortcut("shift+cmd+tab"), among: triggers))
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: shortcut("shift+option+space"), among: triggers))
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: shortcut("shift+ctrl+option+tab"), among: triggers))
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: shortcut("ctrl+option+tab"), among: triggers))
    }

    func testDefaultTriggersDoNotConflictWithEachOther() {
        let triggers = Configuration.defaultTriggers
        for t in triggers {
            XCTAssertNil(ShortcutConflicts.reverseConflict(for: t.shortcut, among: triggers), t.shortcut.displayString)
        }
    }

    func testFnIsIgnoredForReverseConflicts() {
        let triggers = [trigger("fn+option+tab")]
        XCTAssertEqual(ShortcutConflicts.reverseConflict(for: shortcut("shift+option+tab"), among: triggers), triggers[0])
        XCTAssertEqual(ShortcutConflicts.reverseConflict(for: shortcut("fn+shift+option+tab"), among: [trigger("option+tab")]),
                       trigger("option+tab"))
    }

    func testFirstConflictInOrderIsReturned() {
        let triggers = [trigger("cmd+tab"), trigger("option+tab", .apps), trigger("fn+option+tab", .activeApp)]
        XCTAssertEqual(ShortcutConflicts.reverseConflict(for: shortcut("shift+option+tab"), among: triggers), triggers[1])
    }

    func testEmptyTriggerList() {
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: .optionTab, among: []))
    }

    func testMultiModifierTriggers() {
        let triggers = [trigger("ctrl+option+`")]
        XCTAssertEqual(ShortcutConflicts.reverseConflict(for: shortcut("ctrl+option+shift+`"), among: triggers), triggers[0])
        XCTAssertNil(ShortcutConflicts.reverseConflict(for: shortcut("ctrl+shift+`"), among: triggers))
    }
}
