import ApplicationServices
import Darwin

/// Private system functions, resolved at runtime.
///
/// Linking them directly (`@_silgen_name`) would make the whole app refuse to launch if
/// a future macOS removed one. Looking them up with `dlsym` means a missing symbol only
/// disables the feature that needs it. Every caller must handle `nil`.
///
/// Functions whose name contains "Copy" or "Create" return a +1 reference: they are
/// declared as returning `Unmanaged<…>?`, and callers balance them with exactly one
/// `takeRetainedValue()`.
enum PrivateAPI {
    typealias AXUIElementGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias CGSSetSymbolicHotKeyEnabled = @convention(c) (Int32, Bool) -> CGError

    /// `CGSConnectionID CGSMainConnectionID(void)`; a connection ID is a C `int`.
    typealias CGSMainConnectionID = @convention(c) () -> Int32
    /// `CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid)` (+1).
    typealias CGSCopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    /// `CFArrayRef CGSCopyWindowsWithOptionsAndTags(CGSConnectionID cid, uint32_t owner,
    /// CFArrayRef spaces, uint32_t options, uint64_t *setTags, uint64_t *clearTags)` (+1).
    /// `spaces` holds CFNumbers of 64-bit Space IDs; the result holds CFNumbers of window IDs.
    typealias CGSCopyWindowsWithOptionsAndTags = @convention(c) (
        Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    /// `OSStatus GetProcessForPID(pid_t pid, ProcessSerialNumber *psn)`. Public but
    /// deprecated since macOS 10.9; looked up here so using it is not a build warning.
    typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    /// `CGError _SLPSSetFrontProcessWithOptions(ProcessSerialNumber *psn, uint32_t wid, uint32_t mode)`.
    typealias SLPSSetFrontProcessWithOptions = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    /// `CGError SLPSPostEventRecordTo(ProcessSerialNumber *psn, uint8_t *record)`.
    typealias SLPSPostEventRecordTo = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    /// Maps an Accessibility window to its window-server ID. Used by every serious window
    /// manager on macOS; there is no public equivalent.
    static let axUIElementGetWindow: AXUIElementGetWindow? = resolve("_AXUIElementGetWindow")

    /// Turns the system's own shortcuts (⌘⇥, ⌘`) off and on.
    static let cgsSetSymbolicHotKeyEnabled: CGSSetSymbolicHotKeyEnabled? = resolve("CGSSetSymbolicHotKeyEnabled")

    // MARK: Windows on other Spaces (Settings → Filters → "Show windows on other Spaces")

    /// This process's connection to the window server, needed by the two calls below.
    static let cgsMainConnectionID: CGSMainConnectionID? = resolve("CGSMainConnectionID")

    /// Every Space of every display, including fullscreen Spaces, and which one is shown.
    static let cgsCopyManagedDisplaySpaces: CGSCopyManagedDisplaySpaces? = resolve("CGSCopyManagedDisplaySpaces")

    /// The windows on given Spaces, front to back. The Accessibility API only reports
    /// windows on the current Space for most apps; there is no public way to ask per Space.
    static let cgsCopyWindowsWithOptionsAndTags: CGSCopyWindowsWithOptionsAndTags? = resolve("CGSCopyWindowsWithOptionsAndTags")

    /// Process serial number for a PID, which the two front-process calls take.
    static let getProcessForPID: GetProcessForPID? = resolve("GetProcessForPID")

    /// Makes a process frontmost with a given window as its key window, bringing only that
    /// window forward and switching to its Space if needed. Used for every switch: public
    /// activation brings all of an app's windows forward and cannot target another Space.
    static let slpsSetFrontProcessWithOptions: SLPSSetFrontProcessWithOptions? = resolve("_SLPSSetFrontProcessWithOptions")

    /// Posts a raw event record to a process; used to make the chosen window key.
    static let slpsPostEventRecordTo: SLPSPostEventRecordTo? = resolve("SLPSPostEventRecordTo")

    /// Windows on other Spaces can be listed.
    static var canListOtherSpaces: Bool {
        cgsMainConnectionID != nil && cgsCopyManagedDisplaySpaces != nil && cgsCopyWindowsWithOptionsAndTags != nil
    }

    /// A single window can be focused through the window server (only that window comes
    /// forward; on another Space, its Space is shown).
    static var canFocusAcrossSpaces: Bool {
        getProcessForPID != nil && slpsSetFrontProcessWithOptions != nil && slpsPostEventRecordTo != nil
    }

    /// Names of the symbols that could not be found, for diagnostics.
    static var missingSymbols: [String] {
        var missing: [String] = []
        if axUIElementGetWindow == nil { missing.append("_AXUIElementGetWindow") }
        if cgsSetSymbolicHotKeyEnabled == nil { missing.append("CGSSetSymbolicHotKeyEnabled") }
        if cgsMainConnectionID == nil { missing.append("CGSMainConnectionID") }
        if cgsCopyManagedDisplaySpaces == nil { missing.append("CGSCopyManagedDisplaySpaces") }
        if cgsCopyWindowsWithOptionsAndTags == nil { missing.append("CGSCopyWindowsWithOptionsAndTags") }
        if getProcessForPID == nil { missing.append("GetProcessForPID") }
        if slpsSetFrontProcessWithOptions == nil { missing.append("_SLPSSetFrontProcessWithOptions") }
        if slpsPostEventRecordTo == nil { missing.append("SLPSPostEventRecordTo") }
        return missing
    }

    private static func resolve<T>(_ name: String) -> T? {
        // RTLD_DEFAULT is the macro ((void *)-2), which Swift does not import.
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let pointer = dlsym(defaultHandle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
