import AppKit
import TapTheTabCore

@MainActor
protocol HotkeyMonitorDelegate: AnyObject {
    /// A trigger shortcut was pressed while no session was active. The monitor has
    /// already started swallowing keys.
    func hotkeyMonitor(_ monitor: HotkeyMonitor, didTrigger trigger: Trigger, reverse: Bool)
    /// A key went down while a session is active (the event was swallowed).
    func hotkeyMonitor(_ monitor: HotkeyMonitor, keyDown press: KeyPress)
    /// Modifier state changed while a session is active.
    func hotkeyMonitor(_ monitor: HotkeyMonitor, modifiersChanged flags: ModifierFlags)
    /// The tap stopped working (permission revoked). The session, if any, should end.
    func hotkeyMonitorDidFail(_ monitor: HotkeyMonitor)
}

/// Global keyboard capture through a CGEventTap (needs Accessibility permission).
///
/// The tap decides synchronously whether to swallow an event, using only its own
/// state; delegate calls are dispatched to the main queue right after.
final class HotkeyMonitor {
    weak var delegate: HotkeyMonitorDelegate?

    /// Shortcuts that open the switcher.
    var triggers: [Trigger] = [] {
        didSet { updateSystemHotkeys() }
    }

    /// While true every key press is swallowed and forwarded to the delegate.
    private(set) var isSessionActive = false

    /// While true, trigger shortcuts are not captured (Settings is recording a shortcut).
    var isMatchingSuspended = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Key that opened or drove the current session, swallowed until it is released so
    /// its autorepeat and key-up don't leak into the window that gets activated.
    private var heldSessionKey: UInt16?

    private static let disabledHotkeysDefaultsKey = "disabledSymbolicHotkeys"

    /// System shortcuts we switched off. Persisted, because the Window Server keeps them off
    /// after a crash; the next launch turns back on any that are no longer wanted.
    private var disabledSymbolicHotkeys: Set<SymbolicHotkey> = HotkeyMonitor.loadDisabledHotkeys() {
        didSet {
            UserDefaults.standard.set(disabledSymbolicHotkeys.map(\.rawValue).sorted(), forKey: Self.disabledHotkeysDefaultsKey)
        }
    }

    private static func loadDisabledHotkeys() -> Set<SymbolicHotkey> {
        let raw = UserDefaults.standard.array(forKey: disabledHotkeysDefaultsKey) as? [Int] ?? []
        return Set(raw.compactMap { SymbolicHotkey(rawValue: Int32(truncatingIfNeeded: $0)) })
    }

    var isRunning: Bool { tap != nil }

    deinit { stop() }

    /// Returns false when the tap cannot be created (usually: no Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("Could not create event tap (Accessibility permission missing?)")
            // Without a tap we can't stand in for ⌘⇥: give it back to the system.
            restoreSystemHotkeys()
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        updateSystemHotkeys()
        Log.hotkey.info("Event tap started")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isSessionActive = false
        heldSessionKey = nil
        restoreSystemHotkeys()
    }

    /// Called by the coordinator when the switcher closes.
    func endSession() { isSessionActive = false }

    /// Called by the coordinator to open a session without a key press (menu item).
    func beginSession() { isSessionActive = true }

    // MARK: - Event handling (main thread, inside the tap callback)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            guard AXIsProcessTrusted() else {
                // Permission was revoked: don't keep a dead tap around.
                isSessionActive = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.hotkeyMonitorDidFail(self)
                }
                return Unmanaged.passUnretained(event)
            }
            // macOS disables slow taps; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if isSessionActive {
                // A modifier release may have happened while the tap was off; re-read the
                // real state so an open switcher can't wait forever for it.
                let flags = ModifierFlags(CGEventSource.flagsState(.combinedSessionState))
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.hotkeyMonitor(self, modifiersChanged: flags)
                }
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let flags = ModifierFlags(event.flags)
            if !isSessionActive, keyCode == heldSessionKey,
               event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                // ⇥ still held after the switcher closed: don't type tabs into the new window.
                return nil
            }
            if isSessionActive {
                heldSessionKey = keyCode
                let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers
                let press = KeyPress(keyCode: keyCode, modifiers: flags, characters: characters)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.hotkeyMonitor(self, keyDown: press)
                }
                return nil
            }
            if !isMatchingSuspended, let found = match(keyCode: keyCode, flags: flags) {
                let trigger = found.trigger
                let reverse = found.reverse
                isSessionActive = true
                heldSessionKey = keyCode
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.hotkeyMonitor(self, didTrigger: trigger, reverse: reverse)
                }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == heldSessionKey {
                heldSessionKey = nil
                return nil
            }
            return isSessionActive ? nil : Unmanaged.passUnretained(event)

        case .flagsChanged:
            if isSessionActive {
                let flags = ModifierFlags(event.flags)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.hotkeyMonitor(self, modifiersChanged: flags)
                }
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// A trigger matches when its key is pressed with exactly its modifiers; holding
    /// ⇧ in addition (when the trigger itself has no ⇧) opens in reverse.
    private func match(keyCode: UInt16, flags: ModifierFlags) -> (trigger: Trigger, reverse: Bool)? {
        let relevant = flags.intersection([.command, .option, .control, .shift])
        for trigger in triggers where trigger.shortcut.keyCode == keyCode {
            let wanted = trigger.shortcut.modifiers.intersection([.command, .option, .control, .shift])
            if relevant == wanted { return (trigger, false) }
            if !wanted.contains(.shift), relevant == wanted.union(.shift) { return (trigger, true) }
        }
        return nil
    }

    // MARK: - System shortcuts (⌘⇥ and ⌘`)

    /// The Window Server handles ⌘⇥ before any event tap sees it, so taking it over
    /// means switching the system shortcut off while we run (and back on when we stop).
    private func updateSystemHotkeys() {
        guard tap != nil else { return }
        var wanted: Set<SymbolicHotkey> = []
        for trigger in triggers where trigger.shortcut.modifiers.contains(.command) {
            if trigger.shortcut.keyCode == KeyCode.tab { wanted.formUnion([.commandTab, .commandShiftTab]) }
            if trigger.shortcut.keyCode == KeyCode.grave { wanted.insert(.commandKeyAboveTab) }
        }
        for hotkey in disabledSymbolicHotkeys.subtracting(wanted) { hotkey.setEnabled(true) }
        for hotkey in wanted.subtracting(disabledSymbolicHotkeys) { hotkey.setEnabled(false) }
        disabledSymbolicHotkeys = wanted
    }

    func restoreSystemHotkeys() {
        for hotkey in disabledSymbolicHotkeys { hotkey.setEnabled(true) }
        disabledSymbolicHotkeys = []
    }
}

/// The system's own shortcuts, switched off while TapTheTab owns them and restored on quit.
enum SymbolicHotkey: Int32, Hashable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 6

    func setEnabled(_ enabled: Bool) {
        // If the private function is missing, ⌘⇥ simply stays with the system.
        _ = PrivateAPI.cgsSetSymbolicHotKeyEnabled?(rawValue, enabled)
    }
}

extension ModifierFlags {
    init(_ flags: CGEventFlags) {
        var result: ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        self = result
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var result: ModifierFlags = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.function) { result.insert(.function) }
        self = result
    }
}
