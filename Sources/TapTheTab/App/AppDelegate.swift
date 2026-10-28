import AppKit
import TapTheTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionsService()
    private let launchAtLogin = LaunchAtLoginService()
    private var configuration: ConfigurationController!
    private var coordinator: SwitcherCoordinator!
    private var statusItem: StatusItemController?
    private var settings: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var permissionTask: Task<Void, Never>?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configuration = ConfigurationController(store: ConfigStore(directory: ConfigStore.defaultDirectory()))
        coordinator = SwitcherCoordinator(configuration: configuration.configuration, permissions: permissions)
        configuration.onExternalChange = { [weak self] newValue in
            self?.configurationChangedOnDisk(newValue)
        }
        configuration.startWatching()

        statusItem = StatusItemController(actions: StatusItemController.Actions(
            showSwitcher: { [weak self] in self?.coordinator.openFromMenu() },
            togglePause: { [weak self] in self?.togglePause() },
            isPaused: { [weak self] in self?.coordinator.isPaused ?? false },
            showSettings: { [weak self] in self?.showSettings() },
            showPermissions: { [weak self] in self?.showOnboarding() },
            accessibilityGranted: { [weak self] in self?.permissions.accessibilityGranted ?? false }
        ))

        installTerminationSignalHandlers()

        if permissions.accessibilityGranted {
            startSwitcher()
        } else {
            showOnboarding()
        }
        Log.app.info("TapTheTab \(AppInfo.version, privacy: .public) started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTask?.cancel()
        coordinator?.stop()
        configuration?.stopWatching()
    }

    /// Launching the app again while it runs opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Startup

    private func startSwitcher() {
        if coordinator.start() {
            permissionTask?.cancel()
            permissionTask = nil
            return
        }
        // The tap can fail for a moment right after permission is granted; keep trying.
        waitForAccessibility()
    }

    private func waitForAccessibility() {
        permissionTask?.cancel()
        permissionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if self.permissions.accessibilityGranted, self.coordinator.start() {
                    self.permissionTask = nil
                    return
                }
            }
        }
    }

    // MARK: - Windows

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions) { [weak self] in
                self?.onboarding = nil
                self?.startSwitcher()
            }
        }
        onboarding?.show()
        if !permissions.accessibilityGranted { waitForAccessibility() }
    }

    private func showSettings() {
        if settings == nil {
            settings = SettingsWindowController(
                configuration: configuration.configuration,
                permissions: permissions,
                launchAtLogin: launchAtLogin,
                configFileURL: configuration.store.fileURL
            ) { [weak self] newValue in
                self?.settingsChanged(newValue)
            }
        }
        settings?.show()
    }

    // MARK: - Configuration

    private func settingsChanged(_ newValue: Configuration) {
        let applied = configuration.update(newValue)
        coordinator.apply(configuration: applied)
        if applied != newValue {
            // Validation changed something; show the user what is actually in effect.
            settings?.update(configuration: applied)
        }
    }

    private func configurationChangedOnDisk(_ newValue: Configuration) {
        coordinator.apply(configuration: newValue)
        settings?.update(configuration: newValue)
    }

    private func togglePause() {
        coordinator.setPaused(!coordinator.isPaused)
    }

    // MARK: - Signals

    /// ⌘⇥ may be switched off system-wide while we own it; make sure `kill` restores it.
    private func installTerminationSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
