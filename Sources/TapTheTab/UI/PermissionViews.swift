import AppKit
import SwiftUI

/// Green check when granted, orange warning otherwise. VoiceOver reads the permission
/// name as the label and "Granted"/"Not granted" as the value.
struct PermissionStatusIcon: View {
    /// The permission's name, e.g. "Accessibility" (already localized).
    let title: String
    let isGranted: Bool

    static func statusText(isGranted: Bool) -> String {
        isGranted ? L10n.tr("Granted") : L10n.tr("Not granted")
    }

    var body: some View {
        Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 20))
            .foregroundColor(isGranted ? Color.green : Color.orange)
            .frame(width: 24)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(Self.statusText(isGranted: isGranted)))
    }
}

/// A permission with its explanation, live status and up to two buttons.
/// All strings are passed in already localized and are shown verbatim.
struct PermissionCardView: View {
    let title: String
    let requirement: String
    let detail: String
    let isGranted: Bool
    let primaryTitle: String
    let primaryAction: () -> Void
    /// Shown even when granted, e.g. "Open System Settings".
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PermissionStatusIcon(title: title, isGranted: isGranted)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: title)
                        .font(.headline)
                    Text(verbatim: requirement)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                Text(verbatim: detail)
                    .font(.callout)
                    .foregroundColor(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: PermissionStatusIcon.statusText(isGranted: isGranted))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isGranted ? Color.green : Color.orange)
                    // The status icon already reads it as its value.
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if !isGranted {
                    Button(primaryTitle) {
                        primaryAction()
                    }
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle) {
                        secondaryAction()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: NSColor.separatorColor), lineWidth: 1)
        )
    }
}
