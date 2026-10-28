import AppKit
import ApplicationServices

/// Thin, typed wrappers over the C Accessibility API.
enum AX {
    static let fullScreenAttribute = "AXFullScreen"
    /// Upper bound for a single AX call so a hung app cannot freeze us.
    static let messagingTimeout: Float = 0.25

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func rawValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        rawValue(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = rawValue(element, attribute) else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = rawValue(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = rawValue(element, attribute) else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = rawValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = rawValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    /// Window frame in global top-left-origin coordinates (same space as CGWindowList).
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute), let size = size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    static func windowID(_ window: AXUIElement) -> CGWindowID? {
        guard let getWindow = PrivateAPI.axUIElementGetWindow else { return nil }
        var id: CGWindowID = 0
        guard getWindow(window, &id) == .success, id != 0 else { return nil }
        return id
    }
}

extension NSScreen {
    /// The CGDirectDisplayID of this screen.
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Frame converted to the global top-left-origin space used by AX and CGWindowList.
    var topLeftFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
