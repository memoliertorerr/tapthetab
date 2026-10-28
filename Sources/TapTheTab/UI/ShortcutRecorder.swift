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

/// Well-known macOS shortcuts a trigger would collide with. Plain values only.
enum ShortcutAdvisor {
    private enum Conflict {
        case spotlight
        case inputSources
        case screenshot
        case screenshotSelection
        case screenshotToolbar
        case quit
        case close
        case hide
        case minimize
        case cycleWindows

        /// Whole sentences, so translations can put the shortcut (`%@`) wherever they need.
        func message(shortcut: String) -> String {
            switch self {
            case .spotlight: return L10n.tr("%@ is Spotlight's shortcut.", shortcut)
            case .inputSources: return L10n.tr("%@ switches input sources.", shortcut)
            case .screenshot: return L10n.tr("%@ takes a screenshot.", shortcut)
            case .screenshotSelection: return L10n.tr("%@ takes a screenshot of a selection.", shortcut)
            case .screenshotToolbar: return L10n.tr("%@ opens the Screenshot toolbar.", shortcut)
            case .quit: return L10n.tr("%@ quits the frontmost app.", shortcut)
            case .close: return L10n.tr("%@ closes windows.", shortcut)
            case .hide: return L10n.tr("%@ hides the frontmost app.", shortcut)
            case .minimize: return L10n.tr("%@ minimizes windows.", shortcut)
            case .cycleWindows:
                return L10n.tr("%@ normally cycles an app's windows; TapTheTab takes it over while running.", shortcut)
            }
        }
    }

    private static let known: [(shortcut: Shortcut, conflict: Conflict)] = [
        (Shortcut(keyCode: KeyCode.space, modifiers: .command), .spotlight),
        (Shortcut(keyCode: KeyCode.space, modifiers: .control), .inputSources),
        (Shortcut(keyCode: 0x14, modifiers: [.shift, .command]), .screenshot),          // 3
        (Shortcut(keyCode: 0x15, modifiers: [.shift, .command]), .screenshotSelection), // 4
        (Shortcut(keyCode: 0x17, modifiers: [.shift, .command]), .screenshotToolbar),   // 5
        (Shortcut(keyCode: 0x0C, modifiers: .command), .quit),                          // Q
        (Shortcut(keyCode: 0x0D, modifiers: .command), .close),                         // W
        (Shortcut(keyCode: 0x04, modifiers: .command), .hide),                          // H
        (Shortcut(keyCode: 0x2E, modifiers: .command), .minimize),                      // M
        (Shortcut(keyCode: KeyCode.grave, modifiers: .command), .cycleWindows),
    ]

    /// A warning when `shortcut` is a common system shortcut, else nil.
    static func systemConflict(for shortcut: Shortcut) -> String? {
        let modifiers = shortcut.modifiers.intersection([.control, .option, .shift, .command])
        for entry in known where entry.shortcut.keyCode == shortcut.keyCode && entry.shortcut.modifiers == modifiers {
            return entry.conflict.message(shortcut: entry.shortcut.displayString)
        }
        return nil
    }
}
