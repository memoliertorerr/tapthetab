import Foundation

/// A key-down event as seen by the platform layer, stripped to what routing needs.
public struct KeyPress: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ModifierFlags
    /// Characters produced ignoring modifiers other than shift (layout aware).
    public var characters: String?

    public init(keyCode: UInt16, modifiers: ModifierFlags = [], characters: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
    }
}

/// Turns key presses into switcher inputs while the switcher is open.
///
/// Rules (documented in the README):
/// - the trigger key cycles forward, with ⇧ it cycles backward;
/// - arrows move, ↩ activates, ⎋ clears the search or closes;
/// - Space with an empty search keeps the switcher open after release;
/// - ⇧Space peeks at the selected window, also while searching;
/// - ⇧W/⇧M/⇧F/⇧H/⇧Q close, minimize, fullscreen, hide, quit; ⇧D moves the window to the
///   next display, ⇧X closes all of the app's windows, ⇧P pins or unpins the app;
/// - the quick-select modifier (`QuickSelect.modifier`) with 1–9 (top row or keypad)
///   switches to that item at once;
/// - any other printable character goes into the search field.
public struct KeyRouter: Sendable {
    public var triggerKeyCode: UInt16
    public var searchEnabled: Bool
    /// Modifiers held as part of the trigger (e.g. ⌘ for ⌘⇥). They are ignored when
    /// deciding whether a key press is text, so searching works while holding them.
    public var triggerModifiers: ModifierFlags

    public static let actionKeys: [Character: WindowAction] = [
        "w": .close, "m": .minimize, "f": .toggleFullscreen, "h": .hideApp, "q": .quitApp,
        "d": .moveToNextDisplay, "x": .closeAppWindows, "p": .togglePin,
    ]

    /// Whether the quick-select modifier with 1–9 picks an item (`Behavior.quickSelect`).
    public var quickSelectEnabled: Bool

    public init(
        triggerKeyCode: UInt16,
        searchEnabled: Bool = true,
        triggerModifiers: ModifierFlags = [],
        quickSelectEnabled: Bool = true
    ) {
        self.triggerKeyCode = triggerKeyCode
        self.searchEnabled = searchEnabled
        self.triggerModifiers = triggerModifiers.subtracting(.shift)
        self.quickSelectEnabled = quickSelectEnabled
    }

    public func route(_ press: KeyPress, isSearching: Bool) -> SwitcherInput? {
        let shift = press.modifiers.contains(.shift)
        switch press.keyCode {
        case triggerKeyCode:
            return shift ? .previous : .next
        case KeyCode.leftArrow: return .moveLeft
        case KeyCode.rightArrow: return .moveRight
        case KeyCode.upArrow: return .moveUp
        case KeyCode.downArrow: return .moveDown
        case KeyCode.home, KeyCode.pageUp: return .first
        case KeyCode.end, KeyCode.pageDown: return .last
        case KeyCode.returnKey, KeyCode.keypadEnter: return .commit
        case KeyCode.escape: return .cancel
        case KeyCode.delete, KeyCode.forwardDelete: return searchEnabled ? .deleteBackward : nil
        case KeyCode.tab: return shift ? .previous : .next
        case KeyCode.space where shift: return .peek
        case KeyCode.space where !isSearching: return .lockOpen
        default: break
        }

        if quickSelectEnabled, let digit = KeyCode.digit(for: press.keyCode), (1...QuickSelect.maxCount).contains(digit) {
            // fn is ignored like shift: some keyboards set it on their own.
            let extra = press.modifiers.subtracting(triggerModifiers).subtracting([.shift, .function])
            if !extra.isEmpty, extra == QuickSelect.modifier(forTriggerModifiers: triggerModifiers) {
                return .quickSelect(index: digit - 1)
            }
        }

        guard let chars = press.characters, let first = chars.first, chars.count == 1 else { return nil }
        // ⌃ and ⌘ chords (other than the trigger, handled above) are not text.
        let extra = press.modifiers.subtracting(triggerModifiers)
        if extra.contains(.control) || extra.contains(.command) { return nil }

        if shift, let action = Self.actionKeys[Character(first.lowercased())] {
            return .action(action)
        }
        guard searchEnabled else { return nil }
        if first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol || first == " " {
            return .type(String(first))
        }
        return nil
    }
}
