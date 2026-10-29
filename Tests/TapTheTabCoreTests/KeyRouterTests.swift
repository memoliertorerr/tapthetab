import XCTest
@testable import TapTheTabCore

final class KeyRouterTests: XCTestCase {
    private let router = KeyRouter(triggerKeyCode: KeyCode.tab)

    private func route(_ code: UInt16, _ mods: ModifierFlags = [], _ chars: String? = nil, searching: Bool = false, router: KeyRouter? = nil) -> SwitcherInput? {
        (router ?? self.router).route(KeyPress(keyCode: code, modifiers: mods, characters: chars), isSearching: searching)
    }

    // MARK: - Trigger key

    func testTriggerKeyCyclesForward() {
        XCTAssertEqual(route(KeyCode.tab, [.option], "\t"), .next)
    }

    func testShiftTriggerCyclesBackward() {
        XCTAssertEqual(route(KeyCode.tab, [.option, .shift], "\t"), .previous)
    }

    func testCustomTriggerKey() {
        let grave = KeyRouter(triggerKeyCode: KeyCode.grave)
        XCTAssertEqual(route(KeyCode.grave, [.option], "`", router: grave), .next)
        XCTAssertEqual(route(KeyCode.grave, [.option, .shift], "~", router: grave), .previous)
        // Tab still cycles even when it is not the trigger.
        XCTAssertEqual(route(KeyCode.tab, [], "\t", router: grave), .next)
        XCTAssertEqual(route(KeyCode.tab, [.shift], "\t", router: grave), .previous)
    }

    func testTriggerKeyWinsOverTypingEvenWhenItIsALetter() {
        let letterTrigger = KeyRouter(triggerKeyCode: KeyCode.a)
        XCTAssertEqual(route(KeyCode.a, [.command], "a", router: letterTrigger), .next)
    }

    // MARK: - Navigation keys

    func testArrows() {
        XCTAssertEqual(route(KeyCode.leftArrow), .moveLeft)
        XCTAssertEqual(route(KeyCode.rightArrow), .moveRight)
        XCTAssertEqual(route(KeyCode.upArrow), .moveUp)
        XCTAssertEqual(route(KeyCode.downArrow), .moveDown)
    }

    func testHomeEndPageKeys() {
        XCTAssertEqual(route(KeyCode.home), .first)
        XCTAssertEqual(route(KeyCode.pageUp), .first)
        XCTAssertEqual(route(KeyCode.end), .last)
        XCTAssertEqual(route(KeyCode.pageDown), .last)
    }

    func testReturnAndEnterCommit() {
        XCTAssertEqual(route(KeyCode.returnKey, [], "\r"), .commit)
        XCTAssertEqual(route(KeyCode.keypadEnter, [], "\u{3}"), .commit)
    }

    func testEscapeCancels() {
        XCTAssertEqual(route(KeyCode.escape, [], "\u{1b}"), .cancel)
        XCTAssertEqual(route(KeyCode.escape, [], "\u{1b}", searching: true), .cancel)
    }

    func testDeleteKeys() {
        XCTAssertEqual(route(KeyCode.delete, [], "\u{7f}", searching: true), .deleteBackward)
        XCTAssertEqual(route(KeyCode.forwardDelete), .deleteBackward)
    }

    // MARK: - Space

    func testSpaceLocksOpenWhenNotSearching() {
        XCTAssertEqual(route(KeyCode.space, [], " "), .lockOpen)
    }

    func testSpaceTypesWhenSearching() {
        XCTAssertEqual(route(KeyCode.space, [], " ", searching: true), .type(" "))
    }

    // MARK: - Actions

    func testShiftLetterActions() {
        let expected: [(UInt16, String, WindowAction)] = [
            (0x0D, "W", .close),
            (0x2E, "M", .minimize),
            (0x03, "F", .toggleFullscreen),
            (0x04, "H", .hideApp),
            (0x0C, "Q", .quitApp),
            (0x02, "D", .moveToNextDisplay),
            (0x07, "X", .closeAppWindows),
            (0x23, "P", .togglePin),
        ]
        for (code, chars, action) in expected {
            XCTAssertEqual(route(code, [.shift, .option], chars), .action(action), chars)
            XCTAssertEqual(route(code, [.shift], chars, searching: true), .action(action), "\(chars) while searching")
        }
    }

    func testActionsWorkWithSearchDisabled() {
        let noSearch = KeyRouter(triggerKeyCode: KeyCode.tab, searchEnabled: false)
        XCTAssertEqual(route(0x0D, [.shift], "W", router: noSearch), .action(.close))
    }

    func testShiftOnNonActionLetterTypesUppercase() {
        XCTAssertEqual(route(0x00, [.shift], "A"), .type("A"))
    }

    func testActionKeysTable() {
        XCTAssertEqual(KeyRouter.actionKeys.count, 8)
        XCTAssertEqual(Set(KeyRouter.actionKeys.values), Set(WindowAction.allCases).subtracting([.focus]))
    }

    // MARK: - Typing

    func testPlainLettersType() {
        XCTAssertEqual(route(0x0D, [], "w"), .type("w"))
        XCTAssertEqual(route(0x00, [.option], "a"), .type("a"))
    }

    func testDigitsPunctuationAndSymbolsType() {
        XCTAssertEqual(route(0x12, [], "1"), .type("1"))
        XCTAssertEqual(route(0x2F, [], "."), .type("."))
        XCTAssertEqual(route(0x18, [.shift], "+"), .type("+"))
        XCTAssertEqual(route(0x99, [], "é"), .type("é"))
    }

    func testControlChordsAreIgnored() {
        XCTAssertNil(route(0x00, [.control], "a"))
        XCTAssertNil(route(0x0D, [.control, .shift], "W"))
    }

    func testMissingOrMultiCharacterTextIsIgnored() {
        XCTAssertNil(route(0x00, [], nil))
        XCTAssertNil(route(0x00, [], ""))
        XCTAssertNil(route(0x00, [], "ab"))
    }

    func testNonPrintableCharactersAreIgnored() {
        XCTAssertNil(route(0x60, [.function], "\u{F708}")) // F5 function-key private-use character
        XCTAssertNil(route(0x99, [], "\u{7}"))
    }

    func testSearchDisabledDropsTyping() {
        let noSearch = KeyRouter(triggerKeyCode: KeyCode.tab, searchEnabled: false)
        XCTAssertNil(route(0x00, [], "a", router: noSearch))
        XCTAssertNil(route(KeyCode.delete, [], "\u{7f}", router: noSearch))
        XCTAssertEqual(route(KeyCode.space, [], " ", router: noSearch), .lockOpen)
        XCTAssertEqual(route(KeyCode.escape, [], nil, router: noSearch), .cancel)
    }

    func testTriggerModifiersDoNotBlockTyping() {
        let control = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.control])
        XCTAssertEqual(control.route(KeyPress(keyCode: 0x01, modifiers: [.control], characters: "s"), isSearching: false), .type("s"))
        let command = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.command])
        XCTAssertEqual(command.route(KeyPress(keyCode: 0x01, modifiers: [.command], characters: "s"), isSearching: false), .type("s"))
    }

    func testChordsBeyondTheTriggerAreNotText() {
        let router = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.option])
        XCTAssertNil(router.route(KeyPress(keyCode: 0x01, modifiers: [.option, .command], characters: "s"), isSearching: false))
        XCTAssertNil(router.route(KeyPress(keyCode: 0x01, modifiers: [.option, .control], characters: "s"), isSearching: false))
    }

    // MARK: - New actions (⇧D, ⇧X, ⇧P)

    func testNewActionLettersWithoutShiftType() {
        XCTAssertEqual(route(0x02, [], "d"), .type("d"))
        XCTAssertEqual(route(0x07, [], "x", searching: true), .type("x"))
        XCTAssertEqual(route(0x23, [.option], "p"), .type("p"))
    }

    func testNewActionsWithSearchDisabled() {
        let noSearch = KeyRouter(triggerKeyCode: KeyCode.tab, searchEnabled: false)
        XCTAssertEqual(route(0x02, [.shift], "D", router: noSearch), .action(.moveToNextDisplay))
        XCTAssertEqual(route(0x07, [.shift], "X", router: noSearch), .action(.closeAppWindows))
        XCTAssertEqual(route(0x23, [.shift], "P", router: noSearch), .action(.togglePin))
    }

    func testNewActionChordsAreNotActions() {
        XCTAssertNil(route(0x23, [.shift, .control], "P"))
        XCTAssertNil(route(0x02, [.shift, .command], "D"))
    }

    // MARK: - Peek (⇧Space)

    func testShiftSpacePeeksInEveryState() {
        XCTAssertEqual(route(KeyCode.space, [.shift], " "), .peek)
        XCTAssertEqual(route(KeyCode.space, [.shift], " ", searching: true), .peek)
        XCTAssertEqual(route(KeyCode.space, [.shift, .option], " "), .peek)
        XCTAssertEqual(route(KeyCode.space, [.shift], nil, searching: true), .peek)
        let noSearch = KeyRouter(triggerKeyCode: KeyCode.tab, searchEnabled: false)
        XCTAssertEqual(route(KeyCode.space, [.shift], " ", router: noSearch), .peek)
    }

    func testPlainSpaceKeepsItsMeaning() {
        XCTAssertEqual(route(KeyCode.space, [], " "), .lockOpen)
        XCTAssertEqual(route(KeyCode.space, [.option], " "), .lockOpen)
        XCTAssertEqual(route(KeyCode.space, [], " ", searching: true), .type(" "))
    }

    func testSpaceTriggerStillCycles() {
        let spaceTrigger = KeyRouter(triggerKeyCode: KeyCode.space, triggerModifiers: [.control])
        XCTAssertEqual(route(KeyCode.space, [.control, .shift], " ", router: spaceTrigger), .previous)
    }

    // MARK: - Quick select

    private let optionTab = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.option])

    func testCommandDigitsQuickSelectWithOptionTrigger() {
        for digit in 1...9 {
            let code = KeyCode.topRowDigits[digit]
            XCTAssertEqual(route(code, [.option, .command], "\(digit)", router: optionTab), .quickSelect(index: digit - 1), "⌘\(digit)")
            XCTAssertEqual(route(code, [.option, .command], "\(digit)", searching: true, router: optionTab),
                           .quickSelect(index: digit - 1), "⌘\(digit) while searching")
        }
    }

    func testKeypadDigitsQuickSelect() {
        for digit in 1...9 {
            let code = KeyCode.keypadDigits[digit]
            XCTAssertEqual(route(code, [.option, .command], "\(digit)", router: optionTab), .quickSelect(index: digit - 1), "keypad \(digit)")
        }
    }

    func testDigitsWithoutTheModifierStillSearch() {
        XCTAssertEqual(route(KeyCode.topRowDigits[1], [.option], "1", router: optionTab), .type("1"))
        XCTAssertEqual(route(KeyCode.topRowDigits[9], [], "9", router: optionTab), .type("9"))
        XCTAssertEqual(route(KeyCode.keypadDigits[3], [.option], "3", router: optionTab), .type("3"))
        XCTAssertEqual(route(KeyCode.topRowDigits[5], [.option], "5", searching: true, router: optionTab), .type("5"))
    }

    func testCommandZeroIsNotQuickSelect() {
        XCTAssertNil(route(KeyCode.topRowDigits[0], [.option, .command], "0", router: optionTab))
        XCTAssertNil(route(KeyCode.keypadDigits[0], [.option, .command], "0", router: optionTab))
    }

    func testOtherModifiersWithDigitsAreNotQuickSelect() {
        XCTAssertNil(route(KeyCode.topRowDigits[1], [.option, .control], "1", router: optionTab))
        XCTAssertNil(route(KeyCode.topRowDigits[1], [.option, .command, .control], "1", router: optionTab))
    }

    func testShiftAndFnAreIgnoredForQuickSelect() {
        XCTAssertEqual(route(KeyCode.topRowDigits[2], [.option, .command, .shift], "@", router: optionTab), .quickSelect(index: 1))
        XCTAssertEqual(route(KeyCode.keypadDigits[4], [.option, .command, .function], "4", router: optionTab), .quickSelect(index: 3))
    }

    func testQuickSelectUsesKeyCodesNotCharacters() {
        // Non-ANSI layouts (e.g. AZERTY's "&" on the 1 key) and missing text still work.
        XCTAssertEqual(route(KeyCode.topRowDigits[1], [.option, .command], "&", router: optionTab), .quickSelect(index: 0))
        XCTAssertEqual(route(KeyCode.topRowDigits[7], [.option, .command], nil, router: optionTab), .quickSelect(index: 6))
    }

    func testCommandTriggerUsesControlDigits() {
        let commandTab = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.command])
        XCTAssertEqual(route(KeyCode.topRowDigits[1], [.command, .control], "1", router: commandTab), .quickSelect(index: 0))
        XCTAssertEqual(route(KeyCode.keypadDigits[9], [.command, .control], "9", router: commandTab), .quickSelect(index: 8))
        XCTAssertEqual(route(KeyCode.topRowDigits[1], [.command], "1", router: commandTab), .type("1"), "the held trigger modifier alone types")
    }

    func testCommandControlTriggerUsesOptionDigits() {
        let hyper = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.command, .control])
        XCTAssertEqual(route(KeyCode.topRowDigits[3], [.command, .control, .option], "3", router: hyper), .quickSelect(index: 2))
        XCTAssertEqual(route(KeyCode.topRowDigits[3], [.command, .control], "3", router: hyper), .type("3"))
    }

    func testTriggerWithEveryCandidateModifierHasNoQuickSelect() {
        let all = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.command, .control, .option])
        XCTAssertEqual(route(KeyCode.topRowDigits[1], [.command, .control, .option], "1", router: all), .type("1"))
    }

    func testControlTriggerUsesCommandDigits() {
        let controlTab = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.control])
        XCTAssertEqual(route(KeyCode.topRowDigits[2], [.control, .command], "2", router: controlTab), .quickSelect(index: 1))
    }

    func testQuickSelectDisabled() {
        let off = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: [.option], quickSelectEnabled: false)
        XCTAssertFalse(off.quickSelectEnabled)
        XCTAssertTrue(optionTab.quickSelectEnabled, "on by default")
        XCTAssertNil(route(KeyCode.topRowDigits[1], [.option, .command], "1", router: off), "a ⌘ chord, as before")
        XCTAssertEqual(route(KeyCode.topRowDigits[1], [.option], "1", router: off), .type("1"))
    }

    func testQuickSelectWorksWithSearchDisabled() {
        let noSearch = KeyRouter(triggerKeyCode: KeyCode.tab, searchEnabled: false, triggerModifiers: [.option])
        XCTAssertEqual(route(KeyCode.topRowDigits[4], [.option, .command], "4", router: noSearch), .quickSelect(index: 3))
        XCTAssertNil(route(KeyCode.topRowDigits[4], [.option], "4", router: noSearch))
    }

    func testDigitTriggerKeyStillCycles() {
        let digitTrigger = KeyRouter(triggerKeyCode: KeyCode.topRowDigits[1], triggerModifiers: [.option])
        XCTAssertEqual(route(KeyCode.topRowDigits[1], [.option, .command], "1", router: digitTrigger), .next)
    }

    func testDigitKeyCodes() {
        XCTAssertEqual(KeyCode.topRowDigits.count, 10)
        XCTAssertEqual(KeyCode.keypadDigits.count, 10)
        for digit in 0...9 {
            XCTAssertEqual(KeyCode.digit(for: KeyCode.topRowDigits[digit]), digit)
            XCTAssertEqual(KeyCode.digit(for: KeyCode.keypadDigits[digit]), digit)
            // The top-row codes agree with the name table used for shortcuts.
            XCTAssertEqual(KeyCode.code(forName: "\(digit)"), KeyCode.topRowDigits[digit])
        }
        XCTAssertEqual(KeyCode.keypadDigits[1], 0x53)
        XCTAssertEqual(KeyCode.keypadDigits[9], 0x5C)
        XCTAssertNil(KeyCode.digit(for: KeyCode.a))
        XCTAssertNil(KeyCode.digit(for: KeyCode.keypadEnter))
        XCTAssertNil(KeyCode.digit(for: 0x5A)) // between keypad 7 and 8: F20, not a digit
        XCTAssertEqual(Set(KeyCode.topRowDigits + KeyCode.keypadDigits).count, 20)
    }
}
