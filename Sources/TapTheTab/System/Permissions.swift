import AppKit
import ApplicationServices

/// Accessibility (required) and Screen Recording (optional, previews only).
@MainActor
final class PermissionsService: PermissionsProviding {
    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted { openAccessibilitySettings() }
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() { openScreenRecordingSettings() }
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
