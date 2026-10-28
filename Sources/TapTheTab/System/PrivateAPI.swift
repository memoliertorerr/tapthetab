import ApplicationServices
import Darwin

/// Private system functions, resolved at runtime.
///
/// Linking them directly (`@_silgen_name`) would make the whole app refuse to launch if
/// a future macOS removed one. Looking them up with `dlsym` means a missing symbol only
/// disables the feature that needs it. Every caller must handle `nil`.
enum PrivateAPI {
    typealias AXUIElementGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias CGSSetSymbolicHotKeyEnabled = @convention(c) (Int32, Bool) -> CGError

    /// Maps an Accessibility window to its window-server ID. Used by every serious window
    /// manager on macOS; there is no public equivalent.
    static let axUIElementGetWindow: AXUIElementGetWindow? = resolve("_AXUIElementGetWindow")

    /// Turns the system's own shortcuts (⌘⇥, ⌘`) off and on.
    static let cgsSetSymbolicHotKeyEnabled: CGSSetSymbolicHotKeyEnabled? = resolve("CGSSetSymbolicHotKeyEnabled")

    /// Names of the symbols that could not be found, for diagnostics.
    static var missingSymbols: [String] {
        var missing: [String] = []
        if axUIElementGetWindow == nil { missing.append("_AXUIElementGetWindow") }
        if cgsSetSymbolicHotKeyEnabled == nil { missing.append("CGSSetSymbolicHotKeyEnabled") }
        return missing
    }

    private static func resolve<T>(_ name: String) -> T? {
        // RTLD_DEFAULT is the macro ((void *)-2), which Swift does not import.
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let pointer = dlsym(defaultHandle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
