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
        XCTAssertEqual(KeyRouter.actionKeys.count, 5)
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
}
