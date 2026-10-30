import AppKit
import SwiftUI
import TapTheTabCore

struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private var showDelayText: String {
        L10n.tr("%lld ms", Int(model.showDelay.rounded()))
    }

    /// The preview sizes offered, plus a hand-edited value from config.json so the
    /// picker never shows an empty selection.
    private var previewPercentChoices: [Int] {
        var choices = [50, 66, 75, 100]
        let current = model.configuration.appearance.largePreviewPercent
        if !choices.contains(current) {
            choices.append(current)
            choices.sort()
        }
        return choices
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

                Toggle(L10n.tr("Show app names"), isOn: $model.configuration.appearance.showAppName)

                Toggle(isOn: $model.configuration.appearance.groupByApp) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Group windows by app"))
                        Text(L10n.tr("Apps follow their most recent window. The list style shows a heading per app."))
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }

                Toggle(isOn: $model.configuration.appearance.animations) {
                    Text(L10n.tr("Animations"))
                    Text(L10n.tr("The switcher fades in and the selection slides. Always off while Reduce Motion is on."))
                }
            }

            Section {
                Toggle(isOn: $model.configuration.appearance.showPreviews) {
                    Text(L10n.tr("Show live window previews"))
                    Text(L10n.tr("Needs the Screen Recording permission. Previews stay in memory and are never saved."))
                }
                if model.configuration.appearance.showPreviews {
                    Toggle(isOn: $model.configuration.appearance.windowThumbnails) {
                        Text(L10n.tr("Window thumbnails in the switcher"))
                        Text(L10n.tr("Cards and list rows show each window instead of only its app icon; list rows get taller."))
                    }
                    Toggle(isOn: $model.configuration.appearance.showLargePreview) {
                        Text(L10n.tr("Large preview of the selected window"))
                        Text(L10n.tr("On its own card above the switcher. Drag it while the switcher is open to move it."))
                    }
                    if model.configuration.appearance.showLargePreview {
                        Picker(L10n.tr("Large preview size"), selection: $model.configuration.appearance.largePreviewPercent) {
                            ForEach(previewPercentChoices, id: \.self) { percent in
                                Text(L10n.tr("%lld%%", percent)).tag(percent)
                            }
                        }
                    }
                    if !model.screenRecordingGranted {
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
                }
            } header: {
                Text(L10n.tr("Previews"))
            }

            Section {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Switcher position"))
                        Text(L10n.tr("While the switcher is open, drag the list or the large preview to move it. TapTheTab remembers where."))
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(L10n.tr("Reset Position")) {
                        model.configuration.appearance.panelPosition = nil
                        model.configuration.appearance.previewPosition = nil
                    }
                    .disabled(model.configuration.appearance.panelPosition == nil
                              && model.configuration.appearance.previewPosition == nil)
                }
            }

            Section {
                Toggle(isOn: $model.configuration.appearance.showMenuBarIcon) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Show menu bar icon"))
                        Text(L10n.tr("When hidden, open TapTheTab again to get to Settings."))
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
                if model.configuration.appearance.showMenuBarIcon {
                    MenuBarIconStylePicker(
                        style: $model.configuration.appearance.menuBarIconStyle,
                        theme: model.configuration.appearance.colorTheme
                    )
                }
            }

            Section {
                Toggle(isOn: $model.configuration.appearance.liquidGlass) {
                    Text(L10n.tr("Liquid Glass"))
                    Text(L10n.tr("A see-through glass panel. Uses the system's Liquid Glass on macOS 26 and later, and a similar look before."))
                }
                Picker(selection: $model.configuration.appearance.glassStyle) {
                    Text(L10n.tr("Clear")).tag(GlassStyle.clear)
                    Text(L10n.tr("Tinted")).tag(GlassStyle.tinted)
                } label: {
                    Text(L10n.tr("Glass"))
                    Text(L10n.tr("Clear is more transparent; Tinted is frosted, with more contrast."))
                }
                .pickerStyle(.segmented)
                .disabled(!model.configuration.appearance.liquidGlass)
            }

            ThemeSettingsSection(theme: $model.configuration.appearance.colorTheme)

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
        .settingsFormStyle(themed: model.isThemed)
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
                Toggle(isOn: $model.configuration.filters.currentDisplayFirst) {
                    // A second Text in a grouped form's label is shown as its subtitle.
                    Text(L10n.tr("List windows on the switcher's display first"))
                    Text(L10n.tr("The switcher appears on the display chosen under Appearance, Show on."))
                }
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

            PinnedAppsSection(model: model)
        }
        .settingsFormStyle(themed: model.isThemed)
        .onAppear {
            model.refreshStatus()
        }
    }
}

/// Settings → Filters → Pinned apps: like the excluded apps, for apps listed first.
struct PinnedAppsSection: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Section {
            if model.configuration.filters.pinnedBundleIDs.isEmpty {
                Text(L10n.tr("No pinned apps."))
                    .foregroundColor(Color.secondary)
            }
            ForEach(model.configuration.filters.pinnedBundleIDs, id: \.self) { bundleID in
                ExcludedAppRow(
                    bundleID: bundleID,
                    info: model.excludedAppInfo(for: bundleID),
                    list: .pinned,
                    onRemove: { model.removePinned(bundleID) }
                )
            }

            HStack(spacing: 8) {
                Menu(L10n.tr("Add running app")) {
                    ForEach(model.pinnableRunningApps) { app in
                        Button {
                            model.addPinned(app.bundleID)
                        } label: {
                            Text(verbatim: app.name)
                        }
                    }
                }
                .fixedSize()
                .disabled(model.pinnableRunningApps.isEmpty)

                Spacer(minLength: 16)

                TextField(L10n.tr("Bundle ID"), text: $model.newPinnedBundleID, prompt: Text(L10n.tr("Bundle ID, e.g. com.example.App")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .onSubmit {
                        model.addTypedPinnedBundleID()
                    }
                Button(L10n.tr("Add")) {
                    model.addTypedPinnedBundleID()
                }
                .disabled(!model.canAddTypedPinnedBundleID)
            }
        } header: {
            Text(L10n.tr("Pinned apps"))
        } footer: {
            Text(L10n.tr("Windows of pinned apps come first. Press ⇧P in the switcher to pin or unpin the selected app."))
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
    }
}

/// Which list an app row belongs to; only the remove button's wording differs.
enum AppListKind {
    case excluded
    case pinned
}

struct ExcludedAppRow: View {
    let bundleID: String
    let info: ExcludedAppInfo
    var list: AppListKind = .excluded
    let onRemove: () -> Void

    private var removeHelp: String {
        switch list {
        case .excluded: return L10n.tr("Remove from the excluded apps")
        case .pinned: return L10n.tr("Remove from the pinned apps")
        }
    }

    private var removeAccessibilityLabel: String {
        switch list {
        case .excluded: return L10n.tr("Remove %@ from the excluded apps", info.name)
        case .pinned: return L10n.tr("Remove %@ from the pinned apps", info.name)
        }
    }

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
            .help(removeHelp)
            .accessibilityLabel(Text(removeAccessibilityLabel))
        }
    }
}

/// The four menu bar icons side by side, drawn as they appear in the menu bar.
struct MenuBarIconStylePicker: View {
    @Binding var style: MenuBarIconStyle
    let theme: ColorTheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(L10n.tr("Menu bar icon"))
            Spacer(minLength: 8)
            ForEach(MenuBarIconStyle.allCases, id: \.self) { option in
                choice(option)
            }
        }
    }

    private func choice(_ option: MenuBarIconStyle) -> some View {
        let selected = option == style
        let name = Self.name(of: option)
        let image = MenuBarIcon.image(for: option, theme: theme)
        return Button {
            style = option
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: image)
                    .renderingMode(image.isTemplate ? .template : .original)
                    .foregroundColor(Color.primary)
                    .frame(width: 40, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: selected ? 2 : 1)
                    )
                Text(verbatim: name)
                    .font(.caption)
                    .foregroundColor(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option == .themed ? L10n.tr("The classic icon in the theme's first color; classic without a theme.") : name)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    static func name(of style: MenuBarIconStyle) -> String {
        switch style {
        case .classic: return L10n.tr("Classic")
        case .filled: return L10n.tr("Filled")
        case .minimal: return L10n.tr("Minimal")
        case .themed: return L10n.tr("Themed")
        }
    }
}
