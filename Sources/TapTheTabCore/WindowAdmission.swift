import Foundation

/// What the platform layer knows about a candidate window, without its title text.
public struct WindowTraits: Equatable, Sendable {
    /// Accessibility role, e.g. "AXWindow".
    public var role: String?
    /// Accessibility subrole, e.g. "AXStandardWindow", "AXDialog", "AXUnknown".
    public var subrole: String?
    public var hasTitle: Bool
    /// Window-server layer, when known (on-screen windows). 0 is the normal layer.
    public var layer: Int?
    /// Window-server alpha, when known.
    public var alpha: Double?
    public var size: Size?

    public init(role: String?, subrole: String?, hasTitle: Bool, layer: Int? = nil, alpha: Double? = nil, size: Size? = nil) {
        self.role = role
        self.subrole = subrole
        self.hasTitle = hasTitle
        self.layer = layer
        self.alpha = alpha
        self.size = size
    }
}

/// Decides which Accessibility windows belong in the switcher.
///
/// - Standard windows always do.
/// - Dialogs only with a title (untitled ones are usually pop-ups and toasts, e.g. from
///   Parallels Coherence or Chromium).
/// - "Unknown" windows only when they look like real app windows: titled, on the normal
///   layer, visible and at least `minimumUnknownSize`. Apps that draw their own window
///   frame report this subrole — CrossOver, Wine, Whisky and Game Porting Toolkit
///   windows, some remote-app windows — and would otherwise be missing.
/// - Everything else (floating panels, sheets, system dialogs, tooltips) never.
public enum WindowAdmission {
    public static let minimumUnknownSize = Size(width: 100, height: 50)

    public static func isSwitchable(_ traits: WindowTraits) -> Bool {
        guard traits.role == "AXWindow" else { return false }
        switch traits.subrole {
        case "AXStandardWindow":
            return true
        case "AXDialog":
            return traits.hasTitle
        case "AXUnknown":
            guard traits.hasTitle else { return false }
            if let layer = traits.layer, layer != 0 { return false }
            if let alpha = traits.alpha, alpha <= 0 { return false }
            guard let size = traits.size else { return false }
            return size.width >= minimumUnknownSize.width && size.height >= minimumUnknownSize.height
        default:
            return false
        }
    }

    /// A short, non-identifying label for diagnostics ("AXFloatingWindow", "none").
    public static func label(for subrole: String?) -> String {
        guard let subrole, !subrole.isEmpty else { return "none" }
        // Only Apple's own AX names; anything else is collapsed so nothing app-specific leaks.
        return subrole.hasPrefix("AX") && subrole.count <= 40 && subrole.allSatisfy({ $0.isLetter }) ? subrole : "other"
    }
}
