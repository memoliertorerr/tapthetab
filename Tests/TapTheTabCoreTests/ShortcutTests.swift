import XCTest
@testable import TapTheTabCore

final class ShortcutTests: XCTestCase {
    // MARK: - Parsing

    func testParseOptionTab() {
        XCTAssertEqual(Shortcut(string: "option+tab"), .optionTab)
    }

    func testParseMultipleModifiersAndBacktick() {
        XCTAssertEqual(Shortcut(string: "cmd+shift+`"), Shortcut(keyCode: KeyCode.grave, modifiers: [.command, .shift]))
    }

    func testParseWithSpacesAndAlias() {
        XCTAssertEqual(Shortcut(string: "ctrl + grave"), Shortcut(keyCode: KeyCode.grave, modifiers: .control))
        XCTAssertEqual(Shortcut(string: "  alt+tab  "), .optionTab)
    }

    func testParseIsCaseInsensitive() {
        XCTAssertEqual(Shortcut(string: "Option+TAB"), .optionTab)
        XCTAssertEqual(Shortcut(string: "CMD+Grave"), .commandGrave)
    }

    func testModifierAliases() {
        let expected: [(String, ModifierFlags)] = [
            ("control", .control), ("ctrl", .control), ("⌃", .control),
            ("option", .option), ("opt", .option), ("alt", .option), ("⌥", .option),
            ("shift", .shift), ("⇧", .shift),
            ("command", .command), ("cmd", .command), ("⌘", .command),
            ("fn", .function), ("function", .function),
        ]
        for (alias, flag) in expected {
            XCTAssertEqual(Shortcut(string: "\(alias)+tab")?.modifiers, flag, alias)
        }
    }

    func testSymbolForm() {
        XCTAssertEqual(Shortcut(string: "⌥+⇥"), .optionTab)
    }

    func testKeyAliases() {
        let expected: [(String, UInt16)] = [
            ("grave", KeyCode.grave), ("backtick", KeyCode.grave), ("esc", KeyCode.escape),
            ("enter", KeyCode.returnKey), ("backspace", KeyCode.delete), ("del", KeyCode.forwardDelete),
            ("spacebar", KeyCode.space), ("leftarrow", KeyCode.leftArrow), ("uparrow", KeyCode.upArrow),
        ]
        for (alias, code) in expected {
            XCTAssertEqual(KeyCode.code(forName: alias), code, alias)
        }
    }

    func testModifierOrderDoesNotMatter() {
        XCTAssertEqual(Shortcut(string: "shift+cmd+tab"), Shortcut(string: "cmd+shift+tab"))
    }

    func testRepeatedModifierIsHarmless() {
        XCTAssertEqual(Shortcut(string: "opt+option+tab"), .optionTab)
    }

    func testKeyWithoutModifiersParses() {
        XCTAssertEqual(Shortcut(string: "f5"), Shortcut(keyCode: 0x60, modifiers: []))
    }

    func testInvalidStringsReturnNil() {
        for bad in ["", "   ", "+", "option+", "option+banana", "hyper+tab", "option++tab", "option+tab+", "key", "keyxyz", "key70000"] {
            XCTAssertNil(Shortcut(string: bad), "\"\(bad)\" should not parse")
        }
    }

    // MARK: - Formatting

    func testStringValue() {
        XCTAssertEqual(Shortcut.optionTab.stringValue, "option+tab")
        XCTAssertEqual(Shortcut(keyCode: KeyCode.grave, modifiers: [.shift, .command, .control]).stringValue, "control+shift+command+`")
        XCTAssertEqual(Shortcut(keyCode: KeyCode.space, modifiers: .function).stringValue, "fn+space")
    }

    func testStringValueRoundTripsForEveryKnownKey() {
        for entry in KeyCode.table {
            let shortcut = Shortcut(keyCode: entry.code, modifiers: [.command, .option])
            XCTAssertEqual(Shortcut(string: shortcut.stringValue), shortcut, entry.name)
        }
    }

    func testKeyTableHasNoDuplicates() {
        XCTAssertEqual(Set(KeyCode.table.map(\.name)).count, KeyCode.table.count)
        XCTAssertEqual(Set(KeyCode.table.map(\.code)).count, KeyCode.table.count)
    }

    func testDisplayString() {
        XCTAssertEqual(Shortcut.optionTab.displayString, "⌥⇥")
        XCTAssertEqual(Shortcut.commandGrave.displayString, "⌘`")
        XCTAssertEqual(Shortcut.optionTab.description, "⌥⇥")
    }

    func testDisplayStringModifierOrder() {
        let s = Shortcut(keyCode: KeyCode.tab, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(s.displayString, "⌃⌥⇧⌘⇥")
        XCTAssertEqual(ModifierFlags([.command, .control]).symbols, "⌃⌘")
        XCTAssertEqual(ModifierFlags([.shift, .option]).names, ["option", "shift"])
    }

    func testUnknownKeyCodeFallbacks() {
        let s = Shortcut(keyCode: 0x5A, modifiers: .option)
        XCTAssertEqual(KeyCode.name(for: 0x5A), "key90")
        XCTAssertEqual(KeyCode.symbol(for: 0x5A), "#90")
        XCTAssertEqual(s.stringValue, "option+key90")
        XCTAssertEqual(s.displayString, "⌥#90")
        XCTAssertEqual(Shortcut(string: s.stringValue), s)
        XCTAssertEqual(KeyCode.code(forName: "KEY90"), 0x5A)
    }

    // MARK: - Codable

    func testEncodesAsPlainString() throws {
        let data = try JSONEncoder().encode([Shortcut.optionTab])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["option+tab"]"#)
    }

    func testDecodesFromPlainString() throws {
        let decoded = try JSONDecoder().decode([Shortcut].self, from: Data(#"["cmd + shift + grave"]"#.utf8))
        XCTAssertEqual(decoded, [Shortcut(keyCode: KeyCode.grave, modifiers: [.command, .shift])])
    }

    func testDecodingUnknownShortcutThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode([Shortcut].self, from: Data(#"["option+banana"]"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode([Shortcut].self, from: Data(#"[{"keyCode": 48}]"#.utf8)))
    }

    func testCodableRoundTrip() throws {
        let shortcuts: [Shortcut] = [.optionTab, .commandTab, .controlTab, .optionGrave, .commandGrave,
                                     Shortcut(keyCode: 0x5A, modifiers: [.function, .shift])]
        let data = try JSONEncoder().encode(shortcuts)
        XCTAssertEqual(try JSONDecoder().decode([Shortcut].self, from: data), shortcuts)
    }

    func testPresetValues() {
        XCTAssertEqual(Shortcut.optionTab, Shortcut(keyCode: 0x30, modifiers: .option))
        XCTAssertEqual(Shortcut.commandTab.modifiers, .command)
        XCTAssertEqual(Shortcut.controlTab.modifiers, .control)
        XCTAssertEqual(Shortcut.optionGrave.keyCode, 0x32)
    }
}
