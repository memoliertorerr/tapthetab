import AppKit
import SwiftUI
import TapTheTabCore

struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $model.configuration.appearance.style) {
                    Text("Grid").tag(LayoutStyle.grid)
                    Text("List").tag(LayoutStyle.list)
                }
                .pickerStyle(.segmented)

                Picker("Size", selection: $model.configuration.appearance.size) {
                    Text("Small").tag(ItemSize.small)
                    Text("Medium").tag(ItemSize.medium)
                    Text("Large").tag(ItemSize.large)
                }
                .pickerStyle(.segmented)

                Toggle("Show live window previews", isOn: $model.configuration.appearance.showPreviews)
                if model.configuration.appearance.showPreviews && !model.screenRecordingGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color.orange)
                        Text("Previews need the Screen Recording permission.")
                            .font(.callout)
                        Spacer(minLength: 8)
                        Button("Grant Screen Recording…") {
                            model.requestScreenRecording()
                        }
                    }
                }

                Toggle("Show app names", isOn: $model.configuration.appearance.showAppName)
            }

            Section {
                Picker("Theme", selection: $model.configuration.appearance.theme) {
                    Text("System").tag(Theme.system)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }

                Picker("Show on", selection: $model.configuration.appearance.placement) {
                    Text("Display with the mouse pointer").tag(DisplayPlacement.mouse)
                    Text("Display with the active window").tag(DisplayPlacement.activeWindow)
                    Text("Main display").tag(DisplayPlacement.main)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("Show delay")
                        Slider(value: $model.showDelay, in: 0...500, step: 10)
                        Text(verbatim: "\(Int(model.showDelay.rounded())) ms")
                            .font(.body.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                    }
                    Text("Quick taps under this delay switch without showing the panel.")
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
                Toggle("Show minimized windows", isOn: $model.configuration.filters.showMinimized)
                Toggle("Show hidden apps", isOn: $model.configuration.filters.showHiddenApps)
                Toggle("Show apps without windows", isOn: $model.configuration.filters.showWindowlessApps)
                Toggle("Only windows on the current Space", isOn: $model.configuration.filters.currentSpaceOnly)
                Toggle("Only windows on the current display", isOn: $model.configuration.filters.currentDisplayOnly)
            } header: {
                Text("Show")
            }

            Section {
                if model.configuration.filters.excludedBundleIDs.isEmpty {
                    Text("No excluded apps.")
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
                    Menu("Add running app") {
                        ForEach(model.addableRunningApps) { app in
                            Button(app.name) {
                                model.addExcluded(app.bundleID)
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(model.addableRunningApps.isEmpty)

                    Spacer(minLength: 16)

                    TextField("Bundle ID", text: $model.newBundleID, prompt: Text("Bundle ID, e.g. com.example.App"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit {
                            model.addTypedBundleID()
                        }
                    Button("Add") {
                        model.addTypedBundleID()
                    }
                    .disabled(!model.canAddTypedBundleID)
                }
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Windows of excluded apps never appear in the switcher.")
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
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 18))
                    .frame(width: 22, height: 22)
                    .foregroundColor(Color.secondary)
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
            .help("Remove from the excluded apps")
        }
    }
}
