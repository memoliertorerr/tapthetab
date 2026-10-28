import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingViewModel

    private var appIcon: NSImage {
        let icon: NSImage? = NSApp.applicationIconImage
        return icon ?? NSImage()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Welcome to TapTheTab"))
                        .font(.title.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.tr("Hold ⌥ and press ⇥ to see every window. Type to search. Release to switch."))
                        .foregroundColor(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PermissionCardView(
                title: L10n.tr("Accessibility"),
                requirement: L10n.tr("Required"),
                detail: L10n.tr("Lets TapTheTab see your windows and listen for its shortcut."),
                isGranted: model.accessibilityGranted,
                primaryTitle: L10n.tr("Open System Settings"),
                primaryAction: { model.requestAccessibility() },
                secondaryTitle: nil,
                secondaryAction: nil
            )

            PermissionCardView(
                title: L10n.tr("Screen Recording"),
                requirement: L10n.tr("Optional"),
                detail: L10n.tr("Only needed for live window previews. You can turn this on later."),
                isGranted: model.screenRecordingGranted,
                primaryTitle: L10n.tr("Open System Settings"),
                primaryAction: { model.requestScreenRecording() },
                secondaryTitle: nil,
                secondaryAction: nil
            )

            Spacer(minLength: 0)

            HStack {
                if !model.accessibilityGranted {
                    Text(L10n.tr("Waiting for Accessibility permission…"))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                Spacer()
                Button(L10n.tr("Done")) {
                    model.done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.accessibilityGranted)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }
}
