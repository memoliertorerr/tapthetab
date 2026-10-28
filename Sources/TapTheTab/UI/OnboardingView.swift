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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to TapTheTab")
                        .font(.title.weight(.semibold))
                    Text("Hold ⌥ and press ⇥ to see every window. Type to search. Release to switch.")
                        .foregroundColor(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PermissionCardView(
                title: "Accessibility",
                requirement: "Required",
                detail: "Lets TapTheTab see your windows and listen for its shortcut.",
                isGranted: model.accessibilityGranted,
                primaryTitle: "Open System Settings",
                primaryAction: { model.requestAccessibility() },
                secondaryTitle: nil,
                secondaryAction: nil
            )

            PermissionCardView(
                title: "Screen Recording",
                requirement: "Optional",
                detail: "Only needed for live window previews. You can turn this on later.",
                isGranted: model.screenRecordingGranted,
                primaryTitle: "Open System Settings",
                primaryAction: { model.requestScreenRecording() },
                secondaryTitle: nil,
                secondaryAction: nil
            )

            Spacer(minLength: 0)

            HStack {
                if !model.accessibilityGranted {
                    Text("Waiting for Accessibility permission…")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                Spacer()
                Button("Done") {
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
