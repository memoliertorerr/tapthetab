import AppKit
import SwiftUI
import TapTheTabCore

struct PermissionsSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                PermissionCardView(
                    title: L10n.tr("Accessibility"),
                    requirement: L10n.tr("Required"),
                    detail: L10n.tr("Lets TapTheTab see your windows, listen for its shortcut and switch, close or minimize windows."),
                    isGranted: model.accessibilityGranted,
                    primaryTitle: L10n.tr("Request Access…"),
                    primaryAction: { model.requestAccessibility() },
                    secondaryTitle: L10n.tr("Open System Settings"),
                    secondaryAction: { model.openAccessibilitySettings() }
                )
                PermissionCardView(
                    title: L10n.tr("Screen Recording"),
                    requirement: L10n.tr("Optional"),
                    detail: L10n.tr("Only needed for live window previews. TapTheTab never records or stores your screen."),
                    isGranted: model.screenRecordingGranted,
                    primaryTitle: L10n.tr("Request Access…"),
                    primaryAction: { model.requestScreenRecording() },
                    secondaryTitle: L10n.tr("Open System Settings"),
                    secondaryAction: { model.openScreenRecordingSettings() }
                )
            } footer: {
                Text(L10n.tr("Status refreshes automatically while this window is open."))
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
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: AppInfo.name)
                            .font(.title2.weight(.semibold))
                        Text(verbatim: L10n.tr("Version %@ (build %@)", AppInfo.version, AppInfo.build))
                            .foregroundColor(Color.secondary)
                        Text(L10n.tr("A fast, keyboard-first window switcher for macOS: every window, searchable, one shortcut away."))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Button(L10n.tr("Check for Updates…")) {
                        model.openReleasesPage()
                    }
                    Text(L10n.tr("Opens the releases page in your browser."))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }

            Section {
                Link(L10n.tr("Source code on GitHub"), destination: AppInfo.repositoryURL)
                Link(L10n.tr("Report an issue or request a feature"), destination: AppInfo.issuesURL)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Button(L10n.tr("Copy Diagnostics")) {
                            model.copyDiagnostics()
                        }
                        .disabled(!model.canCopyDiagnostics)
                        if model.diagnosticsCopied {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color.green)
                                    .accessibilityHidden(true)
                                Text(L10n.tr("Copied — paste it into a GitHub issue."))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.caption)
                        }
                    }
                    Text(L10n.tr("Versions, permissions, counts and settings. No window titles or app names."))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Text(L10n.tr("TapTheTab never connects to the internet and collects no data. Settings live in config.json on this Mac."))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(L10n.tr("Reveal config file")) {
                        model.revealConfigFile()
                    }
                    Button(L10n.tr("Open config file")) {
                        model.openConfigFile()
                    }
                }
            } header: {
                Text(L10n.tr("Privacy"))
            }

            Section {
                Text(L10n.tr("MIT License"))
                    .foregroundColor(Color.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
