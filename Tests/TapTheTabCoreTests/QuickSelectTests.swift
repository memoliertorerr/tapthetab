import XCTest
@testable import TapTheTabCore

final class QuickSelectTests: XCTestCase {
    func testMaxCount() {
        XCTAssertEqual(QuickSelect.maxCount, 9)
    }

    func testModifierAvoidsTheTriggersModifiers() {
        let table: [(ModifierFlags, ModifierFlags)] = [
            ([], .command),
            (.option, .command),
            (.control, .command),
            (.shift, .command),
            ([.option, .control], .command),
            (.command, .control),
            ([.command, .option], .control),
            ([.command, .shift], .control),
            ([.command, .control], .option),
            ([.command, .control, .option], .option),
        ]
        for (trigger, expected) in table {
            XCTAssertEqual(QuickSelect.modifier(forTriggerModifiers: trigger), expected, "trigger \(trigger.symbols)")
        }
    }

    func testLabels() {
        XCTAssertEqual(QuickSelect.label(forIndex: 0, triggerModifiers: .option), "⌘1")
        XCTAssertEqual(QuickSelect.label(forIndex: 8, triggerModifiers: .option), "⌘9")
        XCTAssertEqual(QuickSelect.label(forIndex: 2, triggerModifiers: .command), "⌃3")
        XCTAssertEqual(QuickSelect.label(forIndex: 4, triggerModifiers: [.command, .control]), "⌥5")
        XCTAssertEqual((0..<9).compactMap { QuickSelect.label(forIndex: $0, triggerModifiers: []) },
                       ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5", "⌘6", "⌘7", "⌘8", "⌘9"])
    }

    func testNoLabelOutsideTheFirstNine() {
        for index in [-1, 9, 10, 100, Int.max, Int.min] {
            XCTAssertNil(QuickSelect.label(forIndex: index, triggerModifiers: .option), "\(index)")
        }
    }

    func testLabelsMatchRouting() {
        // What the label promises is what the router accepts.
        for trigger: ModifierFlags in [.option, .command, .control, [.command, .control]] {
            let router = KeyRouter(triggerKeyCode: KeyCode.tab, triggerModifiers: trigger)
            let modifier = QuickSelect.modifier(forTriggerModifiers: trigger)
            for index in 0..<QuickSelect.maxCount {
                XCTAssertEqual(QuickSelect.label(forIndex: index, triggerModifiers: trigger), modifier.symbols + "\(index + 1)")
                let press = KeyPress(keyCode: KeyCode.topRowDigits[index + 1], modifiers: trigger.union(modifier), characters: "\(index + 1)")
                XCTAssertEqual(router.route(press, isSearching: false), .quickSelect(index: index))
            }
        }
    }
}
