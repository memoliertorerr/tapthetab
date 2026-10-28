import AppKit
import SwiftUI
import TapTheTabCore

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView(model: model)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            FiltersSettingsView(model: model)
                .tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
            PermissionsSettingsView(model: model)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutSettingsView(model: model)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 520)
    }
}

/// One row of the shortcut list, with a stable identity per (position, value) so the
/// row's local picker state is rebuilt whenever the trigger changes underneath it.
struct TriggerRowItem: Identifiable {
    let index: Int
    let trigger: Trigger
    var id: String { "\(index)|\(trigger.shortcut.stringValue)|\(trigger.scope.rawValue)" }
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
                Toggle("Launch at login", isOn: $model.launchAtLoginEnabled)
                if let error = model.launchAtLoginError {
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundColor(Color.red)
                }
            }

            Section {
                ForEach(triggerRows) { row in
                    TriggerRowView(
                        trigger: row.trigger,
                        options: model.shortcutOptions(including: row.trigger.shortcut),
                        canRemove: model.configuration.triggers.count > 1,
                        onShortcut: { shortcut in model.setShortcut(shortcut, at: row.index) },
                        onScope: { scope in model.setScope(scope, at: row.index) },
                        onRemove: { model.removeTrigger(at: row.index) }
                    )
                }
                Button("Add shortcut") {
                    model.addTrigger()
                }
                .disabled(!model.canAddTrigger)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("⌘⇥ replaces the system app switcher while TapTheTab is running.")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }

            Section {
                Toggle("Release modifier to switch", isOn: $model.configuration.behavior.releaseToSwitch)
                Toggle("Type to search", isOn: $model.configuration.behavior.searchEnabled)
                Toggle("Start on previous window", isOn: $model.configuration.behavior.startOnPrevious)
                Toggle("Select on mouse hover", isOn: $model.configuration.behavior.mouseHoverSelects)
                Toggle("Wrap around at the ends", isOn: $model.configuration.behavior.wrapAround)
            } header: {
                Text("Behaviour")
            }
        }
        .formStyle(.grouped)
    }
}

struct TriggerRowView: View {
    let trigger: Trigger
    let options: [Shortcut]
    let canRemove: Bool
    let onShortcut: (Shortcut) -> Void
    let onScope: (SwitcherScope) -> Void
    let onRemove: () -> Void

    @State private var shortcut: Shortcut
    @State private var scope: SwitcherScope

    init(
        trigger: Trigger,
        options: [Shortcut],
        canRemove: Bool,
        onShortcut: @escaping (Shortcut) -> Void,
        onScope: @escaping (SwitcherScope) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.trigger = trigger
        self.options = options
        self.canRemove = canRemove
        self.onShortcut = onShortcut
        self.onScope = onScope
        self.onRemove = onRemove
        self._shortcut = State(initialValue: trigger.shortcut)
        self._scope = State(initialValue: trigger.scope)
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker("Shortcut", selection: $shortcut) {
                ForEach(options, id: \.self) { option in
                    Text(verbatim: option.displayString).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 96)

            Picker("Shows", selection: $scope) {
                Text("All windows").tag(SwitcherScope.allWindows)
                Text("Current app's windows").tag(SwitcherScope.activeApp)
                Text("Apps").tag(SwitcherScope.apps)
            }
            .labelsHidden()
            .frame(maxWidth: 220)

            Spacer(minLength: 0)

            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!canRemove)
            .help("Remove this shortcut")
        }
        .onChange(of: shortcut) { newValue in
            if newValue != trigger.shortcut { onShortcut(newValue) }
        }
        .onChange(of: scope) { newValue in
            if newValue != trigger.scope { onScope(newValue) }
        }
    }
}
