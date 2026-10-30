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
        // Per-element AX timeouts only cover the element they are set on; this caps every
        // AX call (window elements included) so a hung app can't stall us for 6 s.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        configuration = ConfigurationController(store: ConfigStore(directory: ConfigStore.defaultDirectory()))
        coordinator = SwitcherCoordinator(configuration: configuration.configuration, permissions: permissions)
        configuration.onExternalChange = { [weak self] newValue in
            self?.configurationChangedOnDisk(newValue)
        }
        coordinator.onPositionsChanged = { [weak self] main, preview in
            self?.blocksMoved(main: main, preview: preview)
        }
        coordinator.onPinnedAppsChanged = { [weak self] pinned in
            self?.pinnedAppsChanged(pinned)
        }
        configuration.startWatching()
        coordinator.onMonitorFailure = { [weak self] in
            Log.app.notice("Keyboard capture stopped; waiting for Accessibility permission")
            self?.waitForAccessibility()
        }
        // Fires when any app's Accessibility permission changes; check ours.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityPermissionsChanged(_:)),
            name: Notification.Name("com.apple.accessibility.api"), object: nil)

        statusItem = StatusItemController(actions: StatusItemController.Actions(
            showSwitcher: { [weak self] in self?.coordinator.openFromMenu() },
            togglePause: { [weak self] in self?.togglePause() },
            isPaused: { [weak self] in self?.coordinator.isPaused ?? false },
            showSettings: { [weak self] in self?.showSettings() },
            showPermissions: { [weak self] in self?.showOnboarding() },
            accessibilityGranted: { [weak self] in self?.permissions.accessibilityGranted ?? false }
        ))

        statusItem?.setVisible(configuration.configuration.appearance.showMenuBarIcon)
        statusItem?.setIconStyle(configuration.configuration.appearance.menuBarIconStyle,
                                 theme: configuration.configuration.appearance.colorTheme)
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

    /// `tapthetab://` URLs from launchers, Shortcuts or the terminal (`open tapthetab://switch`).
    /// Only commands that open TapTheTab's own UI exist; see `AutomationCommand`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = AutomationCommand(url: url) else {
                Log.app.notice("Ignored unsupported URL")
                continue
            }
            switch command {
            case .showSwitcher(let scope, let query):
                // Let Launch Services finish activating us before the panel appears.
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator?.openFromAutomation(scope: scope, query: query)
                }
            case .openSettings:
                showSettings()
            }
        }
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

    @objc private func accessibilityPermissionsChanged(_ note: Notification) {
        // The new state is only readable a moment after the notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.coordinator.isStarted else { return }
            if !self.permissions.accessibilityGranted {
                self.coordinator.hotkeyMonitorDidFailFromPermissionChange()
            }
        }
    }

    // MARK: - Windows

    /// The tour of the keys: once after the first permission grant, and from Settings / the menu.
    private func showTour(onlyFirstTime: Bool) {
        let appearance = configuration.configuration.appearance
        let symbols = configuration.configuration.triggers.first?.shortcut.modifiers.symbols ?? ""
        let modifier = symbols.isEmpty ? "⌥" : symbols
        if onlyFirstTime {
            _ = TourWindowController.showIfFirstRun(modifier: modifier, theme: appearance.colorTheme)
        } else {
            TourWindowController.show(modifier: modifier, theme: appearance.colorTheme)
        }
    }

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions) { [weak self] in
                self?.onboarding = nil
                self?.startSwitcher()
                self?.showTour(onlyFirstTime: true)
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
            settings?.diagnosticsProvider = { [unowned self] in self.makeDiagnostics() }
            settings?.onShortcutRecordingChanged = { [weak self] recording in
                self?.coordinator.setShortcutRecording(recording)
            }
        }
        settings?.show()
    }

    /// Facts for a bug report: versions, permissions, counts, settings. Nothing personal.
    private func makeDiagnostics() -> DiagnosticsReport {
        let counts = coordinator.diagnosticsCounts
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = Self.isRunningUnderRosetta ? "x86_64 (Rosetta)" : "x86_64"
        #endif
        return DiagnosticsReport(
            appVersion: AppInfo.version,
            build: AppInfo.build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            accessibilityGranted: permissions.accessibilityGranted,
            screenRecordingGranted: permissions.screenRecordingGranted,
            windowCount: counts.windows,
            appCount: counts.apps,
            watchedAppCount: counts.watchedApps,
            configuration: configuration.configuration,
            otherSpacesListingAvailable: PrivateAPI.canListOtherSpaces,
            focusAcrossSpacesAvailable: PrivateAPI.canFocusAcrossSpaces,
            missingPrivateSymbols: PrivateAPI.missingSymbols,
            lastFullRefreshMilliseconds: counts.fullRefreshMilliseconds,
            lastPartialRefreshMilliseconds: counts.partialRefreshMilliseconds,
            skippedWindowsBySubrole: counts.skippedBySubrole,
            lastSwitchMethod: coordinator.lastSwitchMethod
        )
    }

    /// Apple's documented check: sysctl.proc_translated is 1 under Rosetta.
    private static var isRunningUnderRosetta: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
    }

    // MARK: - Configuration

    private func settingsChanged(_ newValue: Configuration) {
        let applied = configuration.update(newValue)
        coordinator.apply(configuration: applied)
        statusItem?.setVisible(applied.appearance.showMenuBarIcon)
        statusItem?.setIconStyle(applied.appearance.menuBarIconStyle, theme: applied.appearance.colorTheme)
        if applied != newValue {
            // Validation changed something; show the user what is actually in effect.
            settings?.update(configuration: applied)
        }
    }

    /// The user dragged a block of the switcher; remember where (Settings can reset it).
    private func blocksMoved(main: BlockPosition?, preview: BlockPosition?) {
        var newValue = configuration.configuration
        newValue.appearance.panelPosition = main
        newValue.appearance.previewPosition = preview
        settingsChanged(newValue)
        settings?.update(configuration: configuration.configuration)
    }

    /// ⇧P in the switcher pinned or unpinned an app.
    private func pinnedAppsChanged(_ pinned: [String]) {
        var newValue = configuration.configuration
        newValue.filters.pinnedBundleIDs = pinned
        settingsChanged(newValue)
        settings?.update(configuration: configuration.configuration)
    }

    private func configurationChangedOnDisk(_ newValue: Configuration) {
        coordinator.apply(configuration: newValue)
        statusItem?.setVisible(newValue.appearance.showMenuBarIcon)
        statusItem?.setIconStyle(newValue.appearance.menuBarIconStyle, theme: newValue.appearance.colorTheme)
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
