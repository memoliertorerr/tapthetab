import AppKit
import SwiftUI
import TapTheTabCore

struct PermissionsSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                PermissionCardView(
                    title: "Accessibility",
                    requirement: "Required",
                    detail: "Lets TapTheTab see your windows, listen for its shortcut and switch, close or minimize windows.",
                    isGranted: model.accessibilityGranted,
                    primaryTitle: "Request Access…",
                    primaryAction: { model.requestAccessibility() },
                    secondaryTitle: "Open System Settings",
                    secondaryAction: { model.openAccessibilitySettings() }
                )
                PermissionCardView(
                    title: "Screen Recording",
                    requirement: "Optional",
                    detail: "Only needed for live window previews. TapTheTab never records or stores your screen.",
                    isGranted: model.screenRecordingGranted,
                    primaryTitle: "Request Access…",
                    primaryAction: { model.requestScreenRecording() },
                    secondaryTitle: "Open System Settings",
                    secondaryAction: { model.openScreenRecordingSettings() }
                )
            } footer: {
                Text("Status refreshes automatically while this window is open.")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshStatus()
        }
    }
}

struct AboutSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private var appIcon: NSImage {
        let icon: NSImage? = NSApp.applicationIconImage
        return icon ?? NSImage()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: AppInfo.name)
                            .font(.title2.weight(.semibold))
                        Text(verbatim: "Version \(AppInfo.version) (build \(AppInfo.build))")
                            .foregroundColor(Color.secondary)
                        Text("A fast, keyboard-first window switcher for macOS: every window, searchable, one shortcut away.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Check for Updates…") {
                        model.openReleasesPage()
                    }
                    Text("Opens the releases page in your browser.")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }

            Section {
                Link("Source code on GitHub", destination: AppInfo.repositoryURL)
                Link("Report an issue or request a feature", destination: AppInfo.issuesURL)
            }

            Section {
                Text("TapTheTab never connects to the internet and collects no data. Settings live in config.json on this Mac.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Reveal config file") {
                        model.revealConfigFile()
                    }
                    Button("Open config file") {
                        model.openConfigFile()
                    }
                }
            } header: {
                Text("Privacy")
            }

            Section {
                Text("MIT License")
                    .foregroundColor(Color.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
