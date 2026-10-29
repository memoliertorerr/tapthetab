import Foundation

/// Picking one of the first items directly with a modifier plus a digit (⌘1…⌘9).
///
/// The modifier must not be part of the trigger shortcut, since the trigger's modifiers
/// are held the whole time the switcher is open (and pressing them with a digit types it
/// into the search field): ⌘ normally, ⌃ when the trigger uses ⌘, ⌥ when it uses ⌘ and ⌃.
public enum QuickSelect {
    /// Digits 1…9 pick the first nine visible items.
    public static let maxCount: Int = 9

    /// The modifier that, with a digit 1–9, picks an item: ⌘, unless the trigger itself
    /// uses ⌘ (then ⌃, unless the trigger uses ⌃ too, then ⌥).
    public static func modifier(forTriggerModifiers trigger: ModifierFlags) -> ModifierFlags {
        if !trigger.contains(.command) { return .command }
        if !trigger.contains(.control) { return .control }
        return .option
    }

    /// "⌘1"…"⌘9" (with the right modifier symbol) for visible indices 0…8, nil beyond.
    public static func label(forIndex index: Int, triggerModifiers: ModifierFlags) -> String? {
        guard index >= 0, index < maxCount else { return nil }
        return modifier(forTriggerModifiers: triggerModifiers).symbols + String(index + 1)
    }
}
