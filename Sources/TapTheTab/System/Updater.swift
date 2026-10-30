import AppKit
import TapTheTabCore

/// Opt-in update checks and verified self-update.
///
/// With automatic checks off (the default) TapTheTab never goes online on its own: the
/// only request is the one the user asks for ("Check for Updates…", "Check Now"). With
/// them on, one GET of GitHub's "latest release" at most once a day (`UpdatePolicy`).
/// Installing verifies the disk image's SHA-256 and the new app's signature (same team
/// and bundle ID as the running app) before replacing anything; see `UpdateInstaller`.
@MainActor
final class Updater: ObservableObject {
    /// The one updater, shared by the menu, Settings and the update window.
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case failed(String)
    }

    enum InstallPhase: Equatable {
        case idle
        case downloading
        case verifying
        case relaunching
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .verifying, .relaunching: return true
            case .idle, .failed: return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var installPhase: InstallPhase = .idle
    /// How the available update can be installed; set when one is found.
    @Published private(set) var installMethod: UpdateInstallMethod = .manual("")
    /// The last successful check (`UserDefaults` key `lastUpdateCheck`).
    @Published private(set) var lastCheck: Date?
    @Published private(set) var automaticChecksEnabled = false
    /// True for a few seconds after the Homebrew command was copied.
    @Published private(set) var commandCopied = false

    private static let lastCheckKey = "lastUpdateCheck"
    /// How often the schedule asks `UpdatePolicy` whether a check is due.
    private static let evaluationNanoseconds: UInt64 = 60 * 60 * 1_000_000_000
    /// First evaluation after launch or turning checks on: lets the network come up.
    private static let initialDelayNanoseconds: UInt64 = 15 * 1_000_000_000
    private static let copyConfirmationSeconds: Double = 3

    private let defaults = UserDefaults.standard
    private var checkTask: Task<Void, Never>?
    private var checkIsAutomatic = false
    private var stateBeforeCheck: State = .idle
    private var scheduleTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var copyToken = 0
    private var window: UpdateWindowController?

    private init() {
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    /// The version of the update found by the last check, for the menu.
    var availableVersion: String? {
        guard case .available(let release) = state else { return nil }
        return release.version.description
    }

    var availableRelease: ReleaseInfo? {
        guard case .available(let release) = state else { return nil }
        return release
    }

    var isChecking: Bool { state == .checking }

    // MARK: - Checking

    /// One check now. User-initiated checks (the menu) also open the update window, which
    /// says when nothing was found and offers the release page when the check fails.
    /// Automatic checks only run while they are turned on.
    func check(userInitiated: Bool) {
        if userInitiated {
            showWindow()
            startCheck(automatic: false)
        } else {
            guard automaticChecksEnabled else { return }
            startCheck(automatic: true)
        }
    }

    /// "Check Now" in Settings: the result shows in place.
    func checkNow() {
        startCheck(automatic: false)
    }

    private func startCheck(automatic: Bool) {
        guard !installPhase.isBusy else { return }
        if checkTask != nil {
            // One request at a time; a click during an automatic check adopts its result.
            if !automatic { checkIsAutomatic = false }
            return
        }
        checkIsAutomatic = automatic
        stateBeforeCheck = state
        state = .checking
        let origin = automatic ? "automatic" : "on request"
        Log.app.info("Checking for updates (\(origin, privacy: .public))")
        checkTask = Task { [weak self] in
            let outcome = await UpdateNetwork.fetchLatest()
            guard !Task.isCancelled else { return }
            self?.finishCheck(outcome)
        }
    }

    private func finishCheck(_ outcome: Result<ReleaseInfo, UpdateFailure>) {
        checkTask = nil
        let automatic = checkIsAutomatic
        switch outcome {
        case .success(let release):
            let now = Date()
            defaults.set(now, forKey: Self.lastCheckKey)
            lastCheck = now
            guard let current = AppVersion(AppInfo.version) else {
                state = .failed(L10n.tr("This build of TapTheTab has no version number to compare."))
                break
            }
            if UpdatePolicy.shouldOffer(release, current: current) {
                installMethod = UpdateInstaller.installMethod()
                if case .failed = installPhase { installPhase = .idle }
                state = .available(release)
                Log.app.notice("Update \(release.version.description, privacy: .public) is available")
            } else {
                state = .upToDate
            }
        case .failure(let failure):
            if automatic, case .available = stateBeforeCheck {
                // Keep offering the update found earlier; an offline moment changes nothing.
                state = stateBeforeCheck
            } else {
                state = .failed(failure.message)
            }
        }
        if !automatic { announceState() }
    }

    // MARK: - Schedule

    /// Turns automatic checks on or off. On: a check soon if one is due, then every hour
    /// `UpdatePolicy` decides again. Off: the schedule stops, an automatic check in flight
    /// is cancelled, and nothing goes online unless the user asks.
    func scheduleAutomaticChecks(enabled: Bool) {
        guard enabled != automaticChecksEnabled || enabled != (scheduleTask != nil) else { return }
        automaticChecksEnabled = enabled
        scheduleTask?.cancel()
        scheduleTask = nil
        guard enabled else {
            if checkTask != nil, checkIsAutomatic {
                checkTask?.cancel()
                checkTask = nil
                state = stateBeforeCheck
            }
            Log.app.info("Automatic update checks off")
            return
        }
        Log.app.info("Automatic update checks on")
        scheduleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.initialDelayNanoseconds)
            while !Task.isCancelled {
                self?.checkIfDue()
                try? await Task.sleep(nanoseconds: Self.evaluationNanoseconds)
            }
        }
    }

    private func checkIfDue() {
        guard UpdatePolicy.isCheckDue(enabled: automaticChecksEnabled, lastCheck: lastCheck, now: Date()) else { return }
        check(userInitiated: false)
    }

    // MARK: - Installing

    /// Downloads, verifies and installs the available update, then quits so the new
    /// version opens. Homebrew installs and copies that cannot replace themselves get the
    /// release page instead.
    func installUpdate() {
        guard case .available(let release) = state, !installPhase.isBusy else { return }
        let method = UpdateInstaller.installMethod()
        installMethod = method
        guard case .selfUpdate(let target) = method else {
            openReleasePage()
            return
        }
        installPhase = .downloading
        announce(L10n.tr("Downloading TapTheTab %@…", release.version.description))
        Log.app.notice("Installing update \(release.version.description, privacy: .public)")
        installTask = Task { [weak self] in
            var workDirectory: URL?
            do {
                let download = try await UpdateNetwork.download(release)
                workDirectory = download.workDirectory
                self?.installPhase = .verifying
                let newApp = try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.prepare(download, release: release, target: target)
                }.value
                guard let self else { return }
                self.installPhase = .relaunching
                try UpdateInstaller.launchReplacement(target: target, newApp: newApp, workDirectory: download.workDirectory)
                // The normal quit path restores ⌘⇥ and stops the event tap.
                NSApp.terminate(nil)
            } catch {
                if let workDirectory { UpdateInstaller.removeWorkDirectory(workDirectory) }
                let message = (error as? UpdateFailure)?.message
                    ?? L10n.tr("The update could not be installed. Download it from the release page.")
                self?.installFailed(message)
            }
        }
    }

    private func installFailed(_ message: String) {
        installTask = nil
        installPhase = .failed(message)
        announce(message)
    }

    // MARK: - Other actions

    /// The available release's page, or the project's releases. Opening a page in the
    /// browser is not a request by TapTheTab.
    func openReleasePage() {
        NSWorkspace.shared.open(availableRelease?.pageURL ?? ReleaseFeed.releasesPageURL)
    }

    func copyHomebrewCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(UpdateInstaller.homebrewCommand, forType: .string)
        copyToken += 1
        let token = copyToken
        if !commandCopied { commandCopied = true }
        announce(L10n.tr("Command copied"))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copyConfirmationSeconds) { [weak self] in
            guard let self, self.copyToken == token else { return }
            self.commandCopied = false
        }
    }

    /// The small "Software Update" window (menu bar → Check for Updates… / Update to …).
    func showWindow() {
        let controller = window ?? UpdateWindowController(updater: self)
        window = controller
        controller.show()
    }

    // MARK: - VoiceOver

    private func announceState() {
        switch state {
        case .upToDate:
            announce(L10n.tr("TapTheTab %@ is up to date.", AppInfo.version))
        case .available(let release):
            announce(L10n.tr("TapTheTab %@ is available.", release.version.description))
        case .failed(let message):
            announce(message)
        case .idle, .checking:
            break
        }
    }

    /// A polite VoiceOver announcement; nothing happens without VoiceOver.
    private func announce(_ text: String) {
        let element: Any
        if let window = NSApplication.shared.keyWindow {
            element = window
        } else {
            element = NSApplication.shared
        }
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}
