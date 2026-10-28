import AppKit
import TapTheTabCore

/// Receives finished recordings, always on the main thread.
@MainActor
protocol ShortcutRecorderDelegate: AnyObject {
    func shortcutRecorder(_ recorder: ShortcutRecorder, didRecord shortcut: Shortcut, forRow index: Int)
}

/// Captures one shortcut from the keyboard for a row of the Settings shortcut list.
///
/// Uses a local event monitor, so it only sees keys while one of TapTheTab's own windows
/// (the Settings window) is key. Deliberately not main-actor isolated: the monitor's
/// handler must decide synchronously whether to swallow an event, and its closure type is
/// not main-actor isolated. Local monitors run on the main thread from the app's event
/// loop; finished recordings reach the delegate through `DispatchQueue.main.async`, the
/// same hop `HotkeyMonitor` uses.
final class ShortcutRecorder: ObservableObject {
    /// Index of the trigger row being recorded, or nil when not recording.
    @Published private(set) var recordingIndex: Int?
    /// Modifiers held right now while recording, for the live preview.
    @Published private(set) var heldModifiers: ModifierFlags = []
    /// Why the last key press was refused (recording continues), or nil.
    @Published private(set) var rejection: String?

    weak var delegate: ShortcutRecorderDelegate?

    private var monitor: Any?

    deinit {
        removeMonitor()
    }

    /// Starts recording for `index`, or moves an ongoing recording to that row.
    func start(index: Int) {
        if recordingIndex != index { recordingIndex = index }
        let held = Self.coreModifiers(from: NSEvent.modifierFlags)
        if heldModifiers != held { heldModifiers = held }
        if rejection != nil { rejection = nil }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] (event: NSEvent) -> NSEvent? in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// Stops recording without a result. Safe to call when not recording.
    func cancel() {
        guard recordingIndex != nil || monitor != nil else { return }
        finish()
    }

    // MARK: - Private

    /// Returns nil for events the recorder consumes.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let index = recordingIndex else { return event }

        switch event.type {
        case .flagsChanged:
            let held = Self.coreModifiers(from: event.modifierFlags)
            if held != heldModifiers { heldModifiers = held }
            // Only observed for the preview; the rest of the app may still need it.
            return event
        case .keyDown:
            break
        default:
            return event
        }

        if event.isARepeat { return nil }

        let keyCode: UInt16 = event.keyCode
        let modifiers: ModifierFlags = Self.coreModifiers(from: event.modifierFlags)

        // ⎋ cancels; ⌫ on its own cancels too.
        if keyCode == KeyCode.escape || (keyCode == KeyCode.delete && modifiers.isEmpty) {
            finish()
            return nil
        }

        let required: ModifierFlags = [.command, .option, .control]
        if modifiers.intersection(required).isEmpty {
            let typed = Shortcut(keyCode: keyCode, modifiers: modifiers).displayString
            let example: String = "⌥" + KeyCode.symbol(for: keyCode)
            rejection = L10n.tr("%@ needs ⌘, ⌥ or ⌃ — for example %@.", typed, example)
            return nil
        }

        let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
        finish()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.shortcutRecorder(self, didRecord: shortcut, forRow: index)
        }
        return nil
    }

    private func finish() {
        removeMonitor()
        if recordingIndex != nil { recordingIndex = nil }
        if !heldModifiers.isEmpty { heldModifiers = [] }
        if rejection != nil { rejection = nil }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// ⌃ ⌥ ⇧ ⌘ only. fn is left out on purpose: AppKit sets it on its own for arrow and
    /// function keys, and the event tap ignores it when matching triggers.
    static func coreModifiers(from flags: NSEvent.ModifierFlags) -> ModifierFlags {
        var result: ModifierFlags = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}

/// Inline message under a trigger row in Settings.
struct ShortcutFeedback: Equatable {
    enum Kind: Equatable {
        case info
        case warning
        case error
    }

    let index: Int
    let kind: Kind
    let message: String
}

/// Localized whole-sentence warnings for the conflicts `ShortcutConflicts` (core) finds.
/// The core reports stable English feature names; they are mapped to sentences here and
/// never shown as they are.
enum ShortcutConflictText {
    /// A warning when `shortcut` is a well-known macOS shortcut, else nil. For a newly
    /// recorded or picked shortcut, so a ⌘` takeover is announced too.
    static func systemConflict(for shortcut: Shortcut) -> String? {
        guard let feature = ShortcutConflicts.systemFeature(for: shortcut) else { return nil }
        let display = shortcut.displayString
        if ShortcutConflicts.isTakenOver(shortcut) {
            return L10n.tr("%@ normally cycles an app's windows; TapTheTab takes it over while running.", display)
        }
        return message(forFeature: feature, shortcut: display)
    }

    /// A warning when `shortcut` equals one of `others` plus ⇧ (or the other way round),
    /// so ⇧-reverse of the shortcut without ⇧ makes one of the two unusable, else nil.
    static func reverseConflict(for shortcut: Shortcut, among others: [Trigger]) -> String? {
        guard let other = ShortcutConflicts.reverseConflict(for: shortcut, among: others) else { return nil }
        let withShift: Shortcut
        let withoutShift: Shortcut
        if shortcut.modifiers.contains(.shift) {
            withShift = shortcut
            withoutShift = other.shortcut
        } else {
            withShift = other.shortcut
            withoutShift = shortcut
        }
        return L10n.tr(
            "%@ can't be used while %@ is a shortcut: ⇧ already reverses it.",
            withShift.displayString,
            withoutShift.displayString
        )
    }

    /// Whole sentences, so translations can put the shortcut (`%@`) wherever they need.
    private static func message(forFeature feature: String, shortcut: String) -> String {
        switch feature {
        case "Spotlight": return L10n.tr("%@ is Spotlight's shortcut.", shortcut)
        case "Input Sources": return L10n.tr("%@ switches input sources.", shortcut)
        case "Screenshot": return L10n.tr("%@ takes a screenshot.", shortcut)
        case "Screenshot of a Selection": return L10n.tr("%@ takes a screenshot of a selection.", shortcut)
        case "Screenshot Toolbar": return L10n.tr("%@ opens the Screenshot toolbar.", shortcut)
        case "Quit App": return L10n.tr("%@ quits the frontmost app.", shortcut)
        case "Close Window": return L10n.tr("%@ closes windows.", shortcut)
        case "Hide App": return L10n.tr("%@ hides the frontmost app.", shortcut)
        case "Minimize Window": return L10n.tr("%@ minimizes windows.", shortcut)
        case "Cycle App Windows":
            return L10n.tr("%@ normally cycles an app's windows; TapTheTab takes it over while running.", shortcut)
        default: return L10n.tr("%@ is already a macOS shortcut.", shortcut)
        }
    }
}
