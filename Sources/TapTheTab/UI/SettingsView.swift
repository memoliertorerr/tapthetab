import AppKit
import SwiftUI
import TapTheTabCore

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label(L10n.tr("General"), systemImage: "gearshape") }
            AppearanceSettingsView(model: model)
                .tabItem { Label(L10n.tr("Appearance"), systemImage: "paintbrush") }
            FiltersSettingsView(model: model)
                .tabItem { Label(L10n.tr("Filters"), systemImage: "line.3.horizontal.decrease.circle") }
            PermissionsSettingsView(model: model)
                .tabItem { Label(L10n.tr("Permissions"), systemImage: "lock.shield") }
            AboutSettingsView(model: model)
                .tabItem { Label(L10n.tr("About"), systemImage: "info.circle") }
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 520)
        // With a color theme on, the whole window takes it (the forms hide their own
        // background, their sections keep theirs).
        .background(
            ThemeBackground(theme: model.configuration.appearance.colorTheme, cornerRadius: 0)
                .ignoresSafeArea()
        )
    }
}

extension View {
    /// The settings tabs' grouped form; over a color theme its own background is hidden
    /// so the theme shows between the sections.
    func settingsFormStyle(themed: Bool) -> some View {
        formStyle(.grouped)
            .scrollContentBackground(themed ? .hidden : .automatic)
    }
}

/// One row of the shortcut list, with a stable identity per (position, value) so the
/// row's local picker state is rebuilt whenever the trigger changes underneath it.
struct TriggerRowItem: Identifiable {
    let index: Int
    let trigger: Trigger
    var id: String {
        "\(index)|\(trigger.shortcut.stringValue)|\(trigger.scope.rawValue)|\(trigger.style?.rawValue ?? "default")"
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private var triggerRows: [TriggerRowItem] {
        var rows: [TriggerRowItem] = []
        for (offset, trigger) in model.configuration.triggers.enumerated() {
            rows.append(TriggerRowItem(index: offset, trigger: trigger))
        }
        return rows
    }

    var body: some View {
        Form {
            Section {
                Toggle(L10n.tr("Launch at login"), isOn: $model.launchAtLoginEnabled)
                if let error = model.launchAtLoginError {
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundColor(Color.red)
                }
            }

            Section {
                ForEach(triggerRows) { row in
                    TriggerRowView(
                        index: row.index,
                        trigger: row.trigger,
                        presets: SettingsViewModel.shortcutPresets,
                        canRemove: model.configuration.triggers.count > 1,
                        feedback: feedback(for: row.index),
                        recorder: model.recorder,
                        onRecord: { model.toggleRecording(at: row.index) },
                        onShortcut: { shortcut in model.assignShortcut(shortcut, at: row.index) },
                        onScope: { scope in model.setScope(scope, at: row.index) },
                        onStyle: { style in model.setStyle(style, at: row.index) },
                        onRemove: { model.removeTrigger(at: row.index) }
                    )
                }
                Button(L10n.tr("Add shortcut")) {
                    model.addTrigger()
                }
                .disabled(!model.canAddTrigger)
            } header: {
                Text(L10n.tr("Shortcuts"))
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("Click a shortcut, then press the new one; ⎋ cancels. ⌘⇥ replaces the system app switcher while TapTheTab is running."))
                    Text(L10n.tr("To record a shortcut that TapTheTab already uses, pick a different one first."))
                }
                .font(.caption)
                .foregroundColor(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(L10n.tr("Release modifier to switch"), isOn: $model.configuration.behavior.releaseToSwitch)
                Toggle(L10n.tr("Type to search"), isOn: $model.configuration.behavior.searchEnabled)
                Toggle(L10n.tr("Start on previous window"), isOn: $model.configuration.behavior.startOnPrevious)
                Toggle(L10n.tr("Select on mouse hover"), isOn: $model.configuration.behavior.mouseHoverSelects)
                Toggle(L10n.tr("Wrap around at the ends"), isOn: $model.configuration.behavior.wrapAround)
                Toggle(isOn: $model.configuration.behavior.quickSelect) {
                    Text(L10n.tr("Quick select with 1–9"))
                    Text(L10n.tr("While the switcher is open, ⌘1–⌘9 pick one of the first nine windows; ⌃1–⌃9 when the shortcut uses ⌘."))
                }
            } header: {
                Text(L10n.tr("Behaviour"))
            }
        }
        .settingsFormStyle(themed: model.isThemed)
        .onDisappear {
            model.cancelRecording()
        }
    }

    private func feedback(for index: Int) -> ShortcutFeedback? {
        guard let feedback = model.shortcutFeedback, feedback.index == index else { return nil }
        return feedback
    }
}

struct TriggerRowView: View {
    let index: Int
    let trigger: Trigger
    let presets: [Shortcut]
    let canRemove: Bool
    let feedback: ShortcutFeedback?
    @ObservedObject var recorder: ShortcutRecorder
    let onRecord: () -> Void
    let onShortcut: (Shortcut) -> Void
    let onScope: (SwitcherScope) -> Void
    let onStyle: (LayoutStyle?) -> Void
    let onRemove: () -> Void

    @State private var scope: SwitcherScope
    /// nil: the style from Appearance.
    @State private var style: LayoutStyle?

    init(
        index: Int,
        trigger: Trigger,
        presets: [Shortcut],
        canRemove: Bool,
        feedback: ShortcutFeedback?,
        recorder: ShortcutRecorder,
        onRecord: @escaping () -> Void,
        onShortcut: @escaping (Shortcut) -> Void,
        onScope: @escaping (SwitcherScope) -> Void,
        onStyle: @escaping (LayoutStyle?) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.index = index
        self.trigger = trigger
        self.presets = presets
        self.canRemove = canRemove
        self.feedback = feedback
        self._recorder = ObservedObject(wrappedValue: recorder)
        self.onRecord = onRecord
        self.onShortcut = onShortcut
        self.onScope = onScope
        self.onStyle = onStyle
        self.onRemove = onRemove
        self._scope = State(initialValue: trigger.scope)
        self._style = State(initialValue: trigger.style)
    }

    private var isRecording: Bool { recorder.recordingIndex == index }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ShortcutRecorderButton(
                    shortcut: trigger.shortcut,
                    isRecording: isRecording,
                    heldModifiers: isRecording ? recorder.heldModifiers : [],
                    action: onRecord
                )

                Menu {
                    ForEach(presets, id: \.self) { option in
                        Button {
                            onShortcut(option)
                        } label: {
                            Text(verbatim: option.displayString)
                        }
                    }
                } label: {
                    Text(L10n.tr("Presets"))
                }
                .fixedSize()
                .help(L10n.tr("Pick a common shortcut"))

                Picker(L10n.tr("Shows"), selection: $scope) {
                    Text(L10n.tr("All windows")).tag(SwitcherScope.allWindows)
                    Text(L10n.tr("Current app's windows")).tag(SwitcherScope.activeApp)
                    Text(L10n.tr("Apps")).tag(SwitcherScope.apps)
                }
                .labelsHidden()
                .frame(maxWidth: 190)
                .padding(.leading, 4)

                Picker(L10n.tr("Style"), selection: $style) {
                    Text(L10n.tr("Default")).tag(LayoutStyle?.none)
                    Text(L10n.tr("Grid")).tag(LayoutStyle?.some(.grid))
                    Text(L10n.tr("List")).tag(LayoutStyle?.some(.list))
                }
                .labelsHidden()
                .fixedSize()
                .help(L10n.tr("Grid or list for this shortcut. Default uses the style set in Appearance."))

                Spacer(minLength: 0)

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .help(L10n.tr("Remove this shortcut"))
                .accessibilityLabel(Text(L10n.tr("Remove shortcut %@", trigger.shortcut.displayString)))
            }

            if isRecording {
                if let rejection = recorder.rejection {
                    ShortcutFeedbackLine(kind: .error, message: rejection)
                } else {
                    Text(L10n.tr("Press the new shortcut with ⌘, ⌥ or ⌃. ⎋ cancels."))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            } else if let feedback {
                ShortcutFeedbackLine(kind: feedback.kind, message: feedback.message)
            }
        }
        .onChange(of: scope) { newValue in
            if newValue != trigger.scope { onScope(newValue) }
        }
        .onChange(of: style) { newValue in
            if newValue != trigger.style { onStyle(newValue) }
        }
    }
}

/// Shows a row's shortcut; click to record a new one.
struct ShortcutRecorderButton: View {
    let shortcut: Shortcut
    let isRecording: Bool
    let heldModifiers: ModifierFlags
    let action: () -> Void

    private var title: String {
        guard isRecording else { return shortcut.displayString }
        return heldModifiers.isEmpty ? L10n.tr("Type shortcut…") : heldModifiers.symbols + "…"
    }

    private var fill: Color {
        isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: NSColor.controlBackgroundColor)
    }

    private var stroke: Color {
        isRecording ? Color.accentColor : Color(nsColor: NSColor.separatorColor)
    }

    private var helpText: String {
        isRecording ? L10n.tr("Press the new shortcut. ⎋ cancels.") : L10n.tr("Click to record a new shortcut")
    }

    private var accessibilityText: String {
        isRecording ? L10n.tr("Recording shortcut") : L10n.tr("Shortcut, %@", shortcut.displayString)
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isRecording ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .frame(minWidth: 112)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: helpText))
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityHint(Text(helpText))
    }
}

/// One line of feedback under a trigger row.
struct ShortcutFeedbackLine: View {
    let kind: ShortcutFeedback.Kind
    let message: String

    private var symbolName: String {
        switch kind {
        case .info: return "arrow.left.arrow.right"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .info: return Color.secondary
        case .warning: return Color.orange
        case .error: return Color.red
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbolName)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundColor(color)
    }
}
