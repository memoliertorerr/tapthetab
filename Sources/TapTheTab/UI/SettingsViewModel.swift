import AppKit
import SwiftUI
import TapTheTabCore

/// A running app that can be added to the exclusion list.
struct RunningAppChoice: Identifiable, Equatable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// Name and icon for an excluded bundle ID, when the app can be found on disk.
struct ExcludedAppInfo {
    let name: String
    let icon: NSImage?
}

/// Editable settings state. Every change to `configuration` is reported through `onChange`,
/// except changes pushed in from outside with `applyExternal(_:)`.
@MainActor
final class SettingsViewModel: ObservableObject {
    static let shortcutPresets: [Shortcut] = [
        .optionTab,
        .commandTab,
        .controlTab,
        .optionGrave,
        .commandGrave,
        Shortcut(keyCode: KeyCode.grave, modifiers: .control),
    ]

    @Published var configuration: Configuration {
        didSet {
            guard !isApplyingExternalChange, configuration != oldValue else { return }
            onChange(configuration)
        }
    }

    /// Mirrors `configuration.appearance.showDelayMilliseconds` as a Double for the slider.
    @Published var showDelay: Double {
        didSet {
            guard !isApplyingExternalChange else { return }
            let milliseconds = Int(showDelay.rounded())
            if configuration.appearance.showDelayMilliseconds != milliseconds {
                configuration.appearance.showDelayMilliseconds = milliseconds
            }
        }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin, launchAtLoginEnabled != oldValue else { return }
            applyLaunchAtLogin(launchAtLoginEnabled)
        }
    }

    @Published private(set) var launchAtLoginError: String? = nil
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var screenRecordingGranted: Bool
    @Published private(set) var runningApps: [RunningAppChoice] = []
    @Published var newBundleID: String = ""

    let configFileURL: URL
    private let permissions: PermissionsProviding
    private let launchAtLogin: LaunchAtLoginProviding
    private let onChange: (Configuration) -> Void
    private var isApplyingExternalChange = false
    private var isSyncingLaunchAtLogin = false
    private var appInfoCache: [String: ExcludedAppInfo] = [:]

    init(
        configuration: Configuration,
        permissions: PermissionsProviding,
        launchAtLogin: LaunchAtLoginProviding,
        configFileURL: URL,
        onChange: @escaping (Configuration) -> Void
    ) {
        self.configuration = configuration
        self.showDelay = Double(configuration.appearance.showDelayMilliseconds)
        self.launchAtLoginEnabled = launchAtLogin.isEnabled
        self.accessibilityGranted = permissions.accessibilityGranted
        self.screenRecordingGranted = permissions.screenRecordingGranted
        self.configFileURL = configFileURL
        self.permissions = permissions
        self.launchAtLogin = launchAtLogin
        self.onChange = onChange
    }

    // MARK: - External updates and polling

    func applyExternal(_ newConfiguration: Configuration) {
        isApplyingExternalChange = true
        if configuration != newConfiguration {
            configuration = newConfiguration
        }
        let delay = Double(newConfiguration.appearance.showDelayMilliseconds)
        if showDelay != delay {
            showDelay = delay
        }
        isApplyingExternalChange = false
    }

    /// Re-reads permission, login-item and running-app state. Only publishes real changes.
    func refreshStatus() {
        let accessibility = permissions.accessibilityGranted
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        let screenRecording = permissions.screenRecordingGranted
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }

        let loginEnabled = launchAtLogin.isEnabled
        if loginEnabled != launchAtLoginEnabled {
            isSyncingLaunchAtLogin = true
            launchAtLoginEnabled = loginEnabled
            isSyncingLaunchAtLogin = false
        }

        let apps = Self.currentRunningApps()
        if apps != runningApps { runningApps = apps }
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        let actual = launchAtLogin.isEnabled
        if actual != launchAtLoginEnabled {
            isSyncingLaunchAtLogin = true
            launchAtLoginEnabled = actual
            isSyncingLaunchAtLogin = false
        }
    }

    // MARK: - Triggers

    var canAddTrigger: Bool { nextUnusedPreset() != nil }

    /// Presets, plus the current shortcut when it is a custom one from the config file.
    func shortcutOptions(including current: Shortcut) -> [Shortcut] {
        var options = Self.shortcutPresets
        if !options.contains(current) {
            options.append(current)
        }
        return options
    }

    /// Picking a shortcut another row already uses swaps the two, so there are never duplicates.
    func setShortcut(_ shortcut: Shortcut, at index: Int) {
        var triggers = configuration.triggers
        guard triggers.indices.contains(index), triggers[index].shortcut != shortcut else { return }
        if let other = triggers.firstIndex(where: { $0.shortcut == shortcut }) {
            triggers[other].shortcut = triggers[index].shortcut
        }
        triggers[index].shortcut = shortcut
        configuration.triggers = triggers
    }

    func setScope(_ scope: SwitcherScope, at index: Int) {
        guard configuration.triggers.indices.contains(index),
              configuration.triggers[index].scope != scope else { return }
        configuration.triggers[index].scope = scope
    }

    func removeTrigger(at index: Int) {
        guard configuration.triggers.count > 1, configuration.triggers.indices.contains(index) else { return }
        configuration.triggers.remove(at: index)
    }

    func addTrigger() {
        guard let shortcut = nextUnusedPreset() else { return }
        configuration.triggers.append(Trigger(shortcut: shortcut, scope: .allWindows))
    }

    private func nextUnusedPreset() -> Shortcut? {
        let used = Set(configuration.triggers.map { $0.shortcut })
        return Self.shortcutPresets.first(where: { !used.contains($0) })
    }

    // MARK: - Excluded apps

    func excludedAppInfo(for bundleID: String) -> ExcludedAppInfo {
        if let cached = appInfoCache[bundleID] { return cached }
        let info: ExcludedAppInfo
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            info = ExcludedAppInfo(name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            info = ExcludedAppInfo(name: bundleID, icon: nil)
        }
        appInfoCache[bundleID] = info
        return info
    }

    /// Running regular apps that are not excluded yet, sorted by name.
    var addableRunningApps: [RunningAppChoice] {
        let excluded = Set(configuration.filters.excludedBundleIDs.map { $0.lowercased() })
        return runningApps.filter { !excluded.contains($0.bundleID.lowercased()) }
    }

    func addExcluded(_ rawBundleID: String) {
        let bundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }
        let lowered = bundleID.lowercased()
        guard !configuration.filters.excludedBundleIDs.contains(where: { $0.lowercased() == lowered }) else { return }
        configuration.filters.excludedBundleIDs.append(bundleID)
    }

    func addTypedBundleID() {
        let typed = newBundleID
        addExcluded(typed)
        newBundleID = ""
    }

    var canAddTypedBundleID: Bool {
        !newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func removeExcluded(_ bundleID: String) {
        configuration.filters.excludedBundleIDs.removeAll(where: { $0 == bundleID })
    }

    private static func currentRunningApps() -> [RunningAppChoice] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var seen = Set<String>()
        var result: [RunningAppChoice] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ownPID,
                  let bundleID = app.bundleIdentifier,
                  bundleID != ownBundleID,
                  seen.insert(bundleID.lowercased()).inserted else { continue }
            result.append(RunningAppChoice(bundleID: bundleID, name: app.localizedName ?? bundleID))
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }

    // MARK: - Permissions and files

    func requestAccessibility() {
        permissions.requestAccessibility()
        refreshStatus()
    }

    func openAccessibilitySettings() {
        permissions.openAccessibilitySettings()
    }

    func requestScreenRecording() {
        permissions.requestScreenRecording()
        refreshStatus()
    }

    func openScreenRecordingSettings() {
        permissions.openScreenRecordingSettings()
    }

    func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([configFileURL])
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configFileURL)
    }
}
