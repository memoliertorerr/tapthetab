import Foundation

/// Plain-value checks for shortcuts a trigger would collide with: well-known macOS
/// shortcuts, and other TapTheTab triggers that differ only by ⇧.
///
/// fn is ignored throughout, the same way the event tap ignores it when matching triggers.
public enum ShortcutConflicts {
    /// Well-known shortcuts and the stable English name of the macOS feature that owns each
    /// by default. The names are UI strings, localized by the app.
    static let known: [(shortcut: Shortcut, feature: String)] = [
        (Shortcut(keyCode: KeyCode.space, modifiers: .command), "Spotlight"),
        (Shortcut(keyCode: KeyCode.space, modifiers: .control), "Input Sources"),
        (Shortcut(keyCode: 0x14, modifiers: [.shift, .command]), "Screenshot"),                // ⇧⌘3
        (Shortcut(keyCode: 0x15, modifiers: [.shift, .command]), "Screenshot of a Selection"), // ⇧⌘4
        (Shortcut(keyCode: 0x17, modifiers: [.shift, .command]), "Screenshot Toolbar"),        // ⇧⌘5
        (Shortcut(keyCode: 0x0C, modifiers: .command), "Quit App"),                            // ⌘Q
        (Shortcut(keyCode: 0x0D, modifiers: .command), "Close Window"),                        // ⌘W
        (Shortcut(keyCode: 0x04, modifiers: .command), "Hide App"),                            // ⌘H
        (Shortcut(keyCode: 0x2E, modifiers: .command), "Minimize Window"),                     // ⌘M
        (Shortcut(keyCode: KeyCode.grave, modifiers: .command), "Cycle App Windows"),          // ⌘`
    ]

    /// System shortcuts TapTheTab switches off while it runs when a trigger uses them
    /// (see `HotkeyMonitor`), so using one is a takeover rather than a collision.
    static let takenOver: Set<Shortcut> = [.commandGrave]

    private static let relevantModifiers: ModifierFlags = [.control, .option, .shift, .command]

    private static func normalized(_ modifiers: ModifierFlags) -> ModifierFlags {
        modifiers.intersection(relevantModifiers)
    }

    /// Name of the macOS feature that owns this shortcut by default, e.g. "Spotlight", or nil.
    ///
    /// ⌘` ("Cycle App Windows") is reported only when it is not already one of
    /// `ownTriggers`: TapTheTab switches that system shortcut off while one of its
    /// triggers uses it, so an existing ⌘` trigger is no longer a conflict. Pass the
    /// configured triggers when re-checking existing rows; leave it empty (the default)
    /// when vetting a newly recorded shortcut, so the takeover is still announced. Use
    /// `isTakenOver(_:)` to word that warning differently from a real collision.
    public static func systemFeature(for shortcut: Shortcut, ownTriggers: [Trigger] = []) -> String? {
        let modifiers = normalized(shortcut.modifiers)
        guard let entry = known.first(where: { $0.shortcut.keyCode == shortcut.keyCode && $0.shortcut.modifiers == modifiers }) else {
            return nil
        }
        if takenOver.contains(entry.shortcut),
           ownTriggers.contains(where: { $0.shortcut.keyCode == shortcut.keyCode && normalized($0.shortcut.modifiers) == modifiers }) {
            return nil
        }
        return entry.feature
    }

    /// True when TapTheTab switches the system shortcut off while a trigger uses it (⌘`),
    /// so the "conflict" is a deliberate takeover that ends when TapTheTab quits.
    public static func isTakenOver(_ shortcut: Shortcut) -> Bool {
        takenOver.contains(Shortcut(keyCode: shortcut.keyCode, modifiers: normalized(shortcut.modifiers)))
    }

    /// A trigger that would make `shortcut` unreachable or be shadowed by it because one
    /// equals the other plus ⇧ (⇧ reverses a trigger without ⇧), or nil.
    ///
    /// Example: with ⌥⇥ configured, ⌥⇧⇥ opens ⌥⇥ in reverse, so a ⌥⇧⇥ trigger either
    /// never fires or takes ⌥⇥'s reverse away, depending on order. Triggers with the same
    /// shortcut as `shortcut` (ignoring fn) are duplicates, not reverse conflicts, and are
    /// skipped; the first conflicting trigger in `triggers` order is returned.
    public static func reverseConflict(for shortcut: Shortcut, among triggers: [Trigger]) -> Trigger? {
        let modifiers = normalized(shortcut.modifiers)
        return triggers.first { trigger in
            guard trigger.shortcut.keyCode == shortcut.keyCode else { return false }
            let other = normalized(trigger.shortcut.modifiers)
            if other == modifiers { return false }
            return (other == modifiers.union(.shift) && !modifiers.contains(.shift))
                || (modifiers == other.union(.shift) && !other.contains(.shift))
        }
    }
}
