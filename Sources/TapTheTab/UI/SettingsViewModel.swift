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
    /// Message under one trigger row after its shortcut changed (swap, system conflict).
    @Published private(set) var shortcutFeedback: ShortcutFeedback? = nil

    /// Builds the diagnostics report for "Copy Diagnostics"; set by the app. Published so
    /// the button enables itself when it is set after the window was built.
    @Published var diagnosticsProvider: (() -> DiagnosticsReport)? = nil
    /// True for a few seconds after the diagnostics were copied, for the confirmation line.
    @Published private(set) var diagnosticsCopied = false

    /// Records new shortcuts for the trigger rows; one row at a time.
    let recorder = ShortcutRecorder()

    let configFileURL: URL
    private let permissions: PermissionsProviding
    private let launchAtLogin: LaunchAtLoginProviding
    private let onChange: (Configuration) -> Void
    private var isApplyingExternalChange = false
    private var isSyncingLaunchAtLogin = false
    private var appInfoCache: [String: ExcludedAppInfo] = [:]
    /// Bumped on every copy, so only the latest copy's timer hides the confirmation.
    private var diagnosticsCopyToken = 0
    private static let diagnosticsConfirmationSeconds: Double = 3

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
        recorder.delegate = self
    }

    // MARK: - External updates and polling

    func applyExternal(_ newConfiguration: Configuration) {
        isApplyingExternalChange = true
        if configuration.triggers != newConfiguration.triggers {
            // Row indices may now mean different shortcuts.
            recorder.cancel()
            if shortcutFeedback != nil { shortcutFeedback = nil }
        }
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

    /// Sets a row's shortcut from the recorder or the presets menu, with inline feedback:
    /// a shortcut another row uses is swapped (and said so); one that clashes with another
    /// row through ⇧-reverse, or a common system shortcut, is allowed with a warning.
    func assignShortcut(_ shortcut: Shortcut, at index: Int) {
        recorder.cancel()
        let triggers = configuration.triggers
        guard triggers.indices.contains(index) else { return }
        let previous = triggers[index].shortcut
        guard shortcut != previous else {
            if shortcutFeedback != nil { shortcutFeedback = nil }
            return
        }

        var feedback: ShortcutFeedback? = nil
        if triggers.contains(where: { $0.shortcut == shortcut }) {
            feedback = ShortcutFeedback(
                index: index,
                kind: .info,
                message: L10n.tr(
                    "%@ was already in use, so that shortcut now uses %@.",
                    shortcut.displayString,
                    previous.displayString
                )
            )
        } else if let warning = ShortcutConflictText.reverseConflict(for: shortcut, among: Self.otherTriggers(triggers, except: index))
                    ?? ShortcutConflictText.systemConflict(for: shortcut) {
            feedback = ShortcutFeedback(index: index, kind: .warning, message: warning)
        }
        setShortcut(shortcut, at: index)
        if shortcutFeedback != feedback { shortcutFeedback = feedback }
    }

    /// Clicking the recorder of the row being recorded stops recording; any other row starts.
    func toggleRecording(at index: Int) {
        if recorder.recordingIndex == index {
            recorder.cancel()
        } else {
            startRecording(at: index)
        }
    }

    func startRecording(at index: Int) {
        guard configuration.triggers.indices.contains(index) else { return }
        if shortcutFeedback != nil { shortcutFeedback = nil }
        recorder.start(index: index)
    }

    func cancelRecording() {
        recorder.cancel()
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
        recorder.cancel()
        if shortcutFeedback != nil { shortcutFeedback = nil }
        configuration.triggers.remove(at: index)
    }

    func addTrigger() {
        guard let shortcut = nextUnusedPreset() else { return }
        recorder.cancel()
        if shortcutFeedback != nil { shortcutFeedback = nil }
        configuration.triggers.append(Trigger(shortcut: shortcut, scope: .allWindows))
    }

    /// Every trigger but the one at `index`.
    private static func otherTriggers(_ triggers: [Trigger], except index: Int) -> [Trigger] {
        var result: [Trigger] = []
        for (offset, trigger) in triggers.enumerated() where offset != index {
            result.append(trigger)
        }
        return result
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

    var canCopyDiagnostics: Bool { diagnosticsProvider != nil }

    /// Puts the diagnostics report (Markdown, no window titles or app names) on the
    /// clipboard and shows a confirmation for a few seconds. Nothing leaves the Mac.
    func copyDiagnostics() {
        guard let provider = diagnosticsProvider else { return }
        let markdown: String = provider().markdown
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)

        diagnosticsCopyToken += 1
        let token = diagnosticsCopyToken
        if !diagnosticsCopied { diagnosticsCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.diagnosticsConfirmationSeconds) { [weak self] in
            guard let self, self.diagnosticsCopyToken == token else { return }
            self.diagnosticsCopied = false
        }
    }

    /// Only opens the browser; TapTheTab itself never checks for updates over the network.
    func openReleasesPage() {
        guard let url = URL(string: "https://github.com/memoliertorerr/tapthetab/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension SettingsViewModel: ShortcutRecorderDelegate {
    func shortcutRecorder(_ recorder: ShortcutRecorder, didRecord shortcut: Shortcut, forRow index: Int) {
        assignShortcut(shortcut, at: index)
    }
}
