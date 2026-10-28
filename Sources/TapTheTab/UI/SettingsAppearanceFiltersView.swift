import AppKit
import SwiftUI
import TapTheTabCore

struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private var showDelayText: String {
        L10n.tr("%lld ms", Int(model.showDelay.rounded()))
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.tr("Style"), selection: $model.configuration.appearance.style) {
                    Text(L10n.tr("Grid")).tag(LayoutStyle.grid)
                    Text(L10n.tr("List")).tag(LayoutStyle.list)
                }
                .pickerStyle(.segmented)

                Picker(L10n.tr("Size"), selection: $model.configuration.appearance.size) {
                    Text(L10n.tr("Small")).tag(ItemSize.small)
                    Text(L10n.tr("Medium")).tag(ItemSize.medium)
                    Text(L10n.tr("Large")).tag(ItemSize.large)
                }
                .pickerStyle(.segmented)

                Toggle(L10n.tr("Show live window previews"), isOn: $model.configuration.appearance.showPreviews)
                if model.configuration.appearance.showPreviews && !model.screenRecordingGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color.orange)
                            .accessibilityHidden(true)
                        Text(L10n.tr("Previews need the Screen Recording permission."))
                            .font(.callout)
                        Spacer(minLength: 8)
                        Button(L10n.tr("Grant Screen Recording…")) {
                            model.requestScreenRecording()
                        }
                    }
                }

                Toggle(L10n.tr("Show app names"), isOn: $model.configuration.appearance.showAppName)
            }

            Section {
                Picker(L10n.tr("Theme"), selection: $model.configuration.appearance.theme) {
                    Text(L10n.tr("System")).tag(Theme.system)
                    Text(L10n.tr("Light")).tag(Theme.light)
                    Text(L10n.tr("Dark")).tag(Theme.dark)
                }

                Picker(L10n.tr("Show on"), selection: $model.configuration.appearance.placement) {
                    Text(L10n.tr("Display with the mouse pointer")).tag(DisplayPlacement.mouse)
                    Text(L10n.tr("Display with the active window")).tag(DisplayPlacement.activeWindow)
                    Text(L10n.tr("Main display")).tag(DisplayPlacement.main)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text(L10n.tr("Show delay"))
                            .accessibilityHidden(true)
                        Slider(value: $model.showDelay, in: 0...500, step: 10)
                            .accessibilityLabel(Text(L10n.tr("Show delay")))
                            .accessibilityValue(Text(showDelayText))
                        Text(verbatim: showDelayText)
                            .font(.body.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    Text(L10n.tr("Quick taps under this delay switch without showing the panel."))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FiltersSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle(L10n.tr("Show minimized windows"), isOn: $model.configuration.filters.showMinimized)
                Toggle(L10n.tr("Show hidden apps"), isOn: $model.configuration.filters.showHiddenApps)
                Toggle(L10n.tr("Show apps without windows"), isOn: $model.configuration.filters.showWindowlessApps)
                Toggle(L10n.tr("Only windows on the current Space"), isOn: $model.configuration.filters.currentSpaceOnly)
                Toggle(L10n.tr("Only windows on the current display"), isOn: $model.configuration.filters.currentDisplayOnly)
                Toggle(isOn: $model.configuration.filters.showOtherSpaces) {
                    // A second Text in a grouped form's label is shown as its subtitle.
                    Text(L10n.tr("Show windows on other Spaces"))
                    Text(L10n.tr("Uses private macOS interfaces; may change with macOS updates."))
                }
            } header: {
                Text(L10n.tr("Show"))
            }

            Section {
                if model.configuration.filters.excludedBundleIDs.isEmpty {
                    Text(L10n.tr("No excluded apps."))
                        .foregroundColor(Color.secondary)
                }
                ForEach(model.configuration.filters.excludedBundleIDs, id: \.self) { bundleID in
                    ExcludedAppRow(
                        bundleID: bundleID,
                        info: model.excludedAppInfo(for: bundleID),
                        onRemove: { model.removeExcluded(bundleID) }
                    )
                }

                HStack(spacing: 8) {
                    Menu(L10n.tr("Add running app")) {
                        ForEach(model.addableRunningApps) { app in
                            Button {
                                model.addExcluded(app.bundleID)
                            } label: {
                                Text(verbatim: app.name)
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(model.addableRunningApps.isEmpty)

                    Spacer(minLength: 16)

                    TextField(L10n.tr("Bundle ID"), text: $model.newBundleID, prompt: Text(L10n.tr("Bundle ID, e.g. com.example.App")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit {
                            model.addTypedBundleID()
                        }
                    Button(L10n.tr("Add")) {
                        model.addTypedBundleID()
                    }
                    .disabled(!model.canAddTypedBundleID)
                }
            } header: {
                Text(L10n.tr("Excluded apps"))
            } footer: {
                Text(L10n.tr("Windows of excluded apps never appear in the switcher."))
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

struct ExcludedAppRow: View {
    let bundleID: String
    let info: ExcludedAppInfo
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let icon = info.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 18))
                    .frame(width: 22, height: 22)
                    .foregroundColor(Color.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: info.name)
                if info.name != bundleID {
                    Text(verbatim: bundleID)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(L10n.tr("Remove from the excluded apps"))
            .accessibilityLabel(Text(L10n.tr("Remove %@ from the excluded apps", info.name)))
        }
    }
}
