import CryptoKit
import Foundation
import Security
import TapTheTabCore

// The blocking and networking parts of updating, free of actor isolation so they run off
// the main thread. `Updater` (main actor) decides when to call them and shows the result.
// Nothing here runs unless the user turned automatic checks on or asked for a check.

/// A failed update step, with a sentence for the user (already localized).
struct UpdateFailure: Error, Sendable {
    let message: String
}

/// Where an available update can be installed from, and how.
enum UpdateInstallMethod: Equatable, Sendable {
    /// TapTheTab may replace itself: Developer ID signed, in a folder the user can write to.
    case selfUpdate(UpdateTarget)
    /// Installed by Homebrew: `brew upgrade --cask tapthetab` keeps Homebrew's records right.
    case homebrew
    /// Only the release page; the sentence says why.
    case manual(String)
}

/// The running app that a self-update replaces and the signature the new one must carry.
struct UpdateTarget: Equatable, Sendable {
    let appURL: URL
    let bundleIdentifier: String
    let teamIdentifier: String
}

/// The files of a release, downloaded into a fresh private directory.
struct DownloadedRelease: Sendable {
    let workDirectory: URL
    let diskImage: URL
    let checksums: URL
}

// MARK: - Network

enum UpdateNetwork {
    /// "TapTheTab/0.10.0": the only identifying detail sent.
    static var userAgent: String { "TapTheTab/\(AppInfo.version)" }

    private static let requestTimeout: TimeInterval = 15
    private static let maximumChecksumsBytes = 64 * 1024
    private static let maximumDiskImageBytes: Int64 = 200 * 1024 * 1024

    /// Ephemeral: no cookies, no cache, no credentials, nothing written to disk.
    private static func makeSession(resourceTimeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }

    private static func request(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: requestTimeout)
        request.httpShouldHandleCookies = false
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// One GET of GitHub's "latest release" for the project.
    static func fetchLatest() async -> Result<ReleaseInfo, UpdateFailure> {
        let session = makeSession(resourceTimeout: 30)
        defer { session.finishTasksAndInvalidate() }
        do {
            let data = try await limitedData(
                session: session,
                request: request(ReleaseFeed.latestURL, accept: "application/vnd.github+json"),
                maximumBytes: ReleaseFeed.maximumResponseBytes
            )
            guard let release = ReleaseFeed.parseLatest(data) else {
                Log.app.error("Update check: the release response could not be read")
                return .failure(UpdateFailure(message: L10n.tr("The release information from GitHub could not be read.")))
            }
            return .success(release)
        } catch let failure as UpdateFailure {
            return .failure(failure)
        } catch {
            Log.app.error("Update check failed: \(String(describing: error), privacy: .public)")
            return .failure(unreachable)
        }
    }

    /// Downloads the release's disk image and SHA256SUMS.txt (only the URLs the release
    /// lists) into a new private directory.
    static func download(_ release: ReleaseInfo) async throws -> DownloadedRelease {
        guard let dmgURL = release.dmgURL, let checksumsURL = release.checksumsURL else {
            throw UpdateFailure(message: L10n.tr("This release has no disk image to install. Download it from the release page."))
        }
        let work = try UpdateInstaller.makeWorkDirectory()
        do {
            let session = makeSession(resourceTimeout: 600)
            defer { session.finishTasksAndInvalidate() }

            let checksumsData = try await limitedData(
                session: session,
                request: request(checksumsURL, accept: "application/octet-stream"),
                maximumBytes: maximumChecksumsBytes
            )
            let checksums = work.appendingPathComponent(ReleaseFeed.checksumsName)
            try checksumsData.write(to: checksums, options: .withoutOverwriting)

            let (temporary, response) = try await session.download(for: request(dmgURL, accept: "application/octet-stream"))
            let diskImage = work.appendingPathComponent(ReleaseFeed.dmgName(for: release.version))
            try FileManager.default.moveItem(at: temporary, to: diskImage)
            try checkStatus(response)
            let size = (try FileManager.default.attributesOfItem(atPath: diskImage.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0, size <= maximumDiskImageBytes else {
                throw UpdateFailure(message: downloadFailedMessage)
            }
            return DownloadedRelease(workDirectory: work, diskImage: diskImage, checksums: checksums)
        } catch {
            UpdateInstaller.removeWorkDirectory(work)
            if let failure = error as? UpdateFailure { throw failure }
            Log.app.error("Update download failed: \(String(describing: error), privacy: .public)")
            throw UpdateFailure(message: downloadFailedMessage)
        }
    }

    /// The body of a 200 response, refusing more than `maximumBytes`.
    private static func limitedData(session: URLSession, request: URLRequest, maximumBytes: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        try checkStatus(response)
        if response.expectedContentLength > Int64(maximumBytes) {
            throw UpdateFailure(message: L10n.tr("The release information from GitHub could not be read."))
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumBytes {
                throw UpdateFailure(message: L10n.tr("The release information from GitHub could not be read."))
            }
        }
        return data
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw unreachable }
        switch http.statusCode {
        case 200:
            return
        case 403, 429:
            Log.app.error("Update request refused (HTTP \(http.statusCode, privacy: .public))")
            throw UpdateFailure(message: L10n.tr("GitHub is limiting requests right now. Try again later."))
        case 404:
            Log.app.error("Update request: not found")
            throw UpdateFailure(message: L10n.tr("No published release was found on GitHub."))
        default:
            Log.app.error("Update request failed (HTTP \(http.statusCode, privacy: .public))")
            throw UpdateFailure(message: L10n.tr("GitHub answered with an error (HTTP %@). Try again later.", String(http.statusCode)))
        }
    }

    private static var unreachable: UpdateFailure {
        UpdateFailure(message: L10n.tr("TapTheTab could not reach GitHub. Check your internet connection and try again."))
    }

    private static var downloadFailedMessage: String {
        L10n.tr("The download failed. Try again later, or download the update from the release page.")
    }
}

// MARK: - Install

enum UpdateInstaller {
    /// The Homebrew command shown instead of a self-update.
    static let homebrewCommand = "brew upgrade --cask tapthetab"

    private static let caskroomPaths = ["/opt/homebrew/Caskroom/tapthetab", "/usr/local/Caskroom/tapthetab"]
    private static let appName = "TapTheTab.app"
    private static let processTimeout: TimeInterval = 120

    /// How the running copy can be updated. Cheap enough to call before every install.
    static func installMethod() -> UpdateInstallMethod {
        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        if appURL.pathComponents.contains("Caskroom")
            || caskroomPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            return .homebrew
        }
        guard appURL.pathExtension == "app" else {
            return .manual(L10n.tr("This copy of TapTheTab cannot update itself. Download the update from the release page."))
        }
        if appURL.path.contains("/AppTranslocation/") {
            return .manual(L10n.tr("macOS runs this copy of TapTheTab from a temporary location. Move TapTheTab to the Applications folder and open it from there, or download the update from the release page."))
        }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, isSafeIdentifier(bundleIdentifier),
              let teamIdentifier = runningTeamIdentifier(), isSafeIdentifier(teamIdentifier) else {
            return .manual(L10n.tr("This copy of TapTheTab is not signed with a Developer ID, so it cannot update itself. Download the update from the release page."))
        }
        let parent = appURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent),
              FileManager.default.isWritableFile(atPath: appURL.path) else {
            return .manual(L10n.tr("TapTheTab is not allowed to replace itself in its folder. Download the update from the release page and install it yourself."))
        }
        return .selfUpdate(UpdateTarget(appURL: appURL, bundleIdentifier: bundleIdentifier, teamIdentifier: teamIdentifier))
    }

    /// A new directory only this user can read (0700) in the user's temporary folder.
    static func makeWorkDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTheTab-Update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
        } catch {
            Log.app.error("Could not create the update folder: \(String(describing: error), privacy: .private)")
            throw UpdateFailure(message: L10n.tr("The update could not be prepared. Download it from the release page."))
        }
        return directory
    }

    static func removeWorkDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Checks the disk image against SHA256SUMS.txt, copies the app out of it and checks
    /// the copy's signature and version. Blocking: call off the main thread. Returns the
    /// verified app inside the work directory.
    static func prepare(_ download: DownloadedRelease, release: ReleaseInfo, target: UpdateTarget) throws -> URL {
        try verifyChecksum(download, release: release)
        let newApp = try extractApp(from: download.diskImage, into: download.workDirectory)
        guard isValidlySigned(newApp, bundleIdentifier: target.bundleIdentifier, teamIdentifier: target.teamIdentifier) else {
            Log.app.error("Update rejected: code signature does not match the running app")
            throw UpdateFailure(message: L10n.tr("The update's code signature could not be verified, so it was not installed."))
        }
        let plist = try? Data(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        let info = plist.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
        guard let versionString = info?["CFBundleShortVersionString"] as? String,
              let version = AppVersion(versionString), version == release.version else {
            Log.app.error("Update rejected: the app's version does not match the release")
            throw UpdateFailure(message: L10n.tr("The update has a different version than the release, so it was not installed."))
        }
        return newApp
    }

    private static func verifyChecksum(_ download: DownloadedRelease, release: ReleaseInfo) throws {
        let mismatch = UpdateFailure(message: L10n.tr("The downloaded file does not match its published checksum, so it was not installed."))
        guard let text = try? String(contentsOf: download.checksums, encoding: .utf8),
              let expected = Checksums.parse(text)[ReleaseFeed.dmgName(for: release.version)] else {
            Log.app.error("Update rejected: no checksum for the disk image")
            throw mismatch
        }
        let actual: String
        do {
            actual = try sha256Hex(of: download.diskImage)
        } catch {
            throw mismatch
        }
        guard actual == expected else {
            Log.app.error("Update rejected: checksum mismatch")
            throw mismatch
        }
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Mounts the (already verified) image read-only and without Finder, copies
    /// TapTheTab.app next to it with `ditto`, and always detaches it again.
    private static func extractApp(from diskImage: URL, into work: URL) throws -> URL {
        let failure = UpdateFailure(message: L10n.tr("The disk image could not be opened, so the update was not installed."))
        let mountPoint = work.appendingPathComponent("mnt", isDirectory: true)
        let destination = work.appendingPathComponent(appName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: false)
        } catch {
            throw failure
        }
        let attached = try? run("/usr/bin/hdiutil", [
            "attach", "-nobrowse", "-readonly", "-noautoopen", "-quiet",
            "-mountpoint", mountPoint.path, diskImage.path,
        ])
        guard attached == 0 else {
            Log.app.error("Update: hdiutil attach failed")
            throw failure
        }
        defer {
            if (try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])) != 0 {
                _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet", "-force"])
            }
        }

        // The app must be a real directory on the image, not a link pointing elsewhere.
        let source = mountPoint.appendingPathComponent(appName, isDirectory: true)
        let type = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.type] as? FileAttributeType
        guard type == .typeDirectory else {
            Log.app.error("Update: the disk image has no TapTheTab.app")
            throw failure
        }
        guard (try? run("/usr/bin/ditto", [source.path, destination.path])) == 0 else {
            Log.app.error("Update: copying the app out of the disk image failed")
            throw failure
        }
        return destination
    }

    // MARK: Code signature

    /// Team ID of the running app's signature; nil for ad-hoc signed or unsigned builds.
    static func runningTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else { return nil }
        return team
    }

    /// True when the bundle is validly signed (all architectures, strict) by an Apple-issued
    /// certificate for the same team and bundle ID as the running app.
    private static func isValidlySigned(_ appURL: URL, bundleIdentifier: String, teamIdentifier: String) -> Bool {
        guard isSafeIdentifier(bundleIdentifier), isSafeIdentifier(teamIdentifier) else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return false }
        let text = "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        if status != errSecSuccess {
            Log.app.error("Update signature check failed (OSStatus \(status, privacy: .public))")
        }
        return status == errSecSuccess
    }

    /// Letters, digits, dots and hyphens only, so the value is safe inside a requirement.
    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x2E || byte == 0x2D
        }
    }

    // MARK: Replacing the app

    /// Waits for TapTheTab (argument 1, a PID) to quit, moves the installed app (2) aside,
    /// copies the verified new app (3) into its place, removes quarantine if present and
    /// opens it. On any failure the old app is put back and reopened. The previous version
    /// goes to the Trash (5, may be empty) and the work directory (4) is removed.
    /// Paths only ever arrive as arguments; nothing is interpolated into this text.
    private static let replaceScript = """
    #!/bin/sh
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    pid="$1"
    target="$2"
    new="$3"
    work="$4"
    trash="$5"

    n=0
    while /bin/kill -0 "$pid" 2>/dev/null; do
        n=$((n + 1))
        if [ "$n" -gt 1200 ]; then
            exit 1
        fi
        /bin/sleep 0.1
    done

    backup="$work/previous/TapTheTab.app"
    if ! /bin/mkdir -p "$work/previous" || ! /bin/mv -f -- "$target" "$backup"; then
        /usr/bin/open -- "$target"
        exit 1
    fi
    if ! /usr/bin/ditto "$new" "$target"; then
        /bin/rm -rf -- "$target"
        /bin/mv -f -- "$backup" "$target"
        /usr/bin/open -- "$target"
        exit 1
    fi
    if /usr/bin/xattr -p com.apple.quarantine "$target" >/dev/null 2>&1; then
        /usr/bin/xattr -dr com.apple.quarantine "$target"
    fi
    /usr/bin/open -- "$target"

    if [ -n "$trash" ] && [ -d "$trash" ] && [ -w "$trash" ]; then
        /bin/mv -f -- "$backup" "$trash/TapTheTab (previous version $(/bin/date +%Y%m%d-%H%M%S)).app"
    fi
    /bin/rm -rf -- "$work"
    exit 0
    """

    /// Starts the replacement script, detached. The caller then quits normally
    /// (`NSApp.terminate`), which restores the system shortcuts; the script waits for that.
    static func launchReplacement(target: UpdateTarget, newApp: URL, workDirectory: URL) throws {
        let failure = UpdateFailure(message: L10n.tr("The update could not be installed. Download it from the release page."))
        // Writable again right before replacing: the folder may have changed since the check.
        let parent = target.appURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent),
              FileManager.default.isWritableFile(atPath: target.appURL.path) else {
            throw UpdateFailure(message: L10n.tr("TapTheTab is not allowed to replace itself in its folder. Download the update from the release page and install it yourself."))
        }
        let script = workDirectory.appendingPathComponent("replace.sh")
        let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: target.appURL, create: false)
        do {
            try replaceScript.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: script.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                script.path,
                String(ProcessInfo.processInfo.processIdentifier),
                target.appURL.path,
                newApp.path,
                workDirectory.path,
                trash?.path ?? "",
            ]
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
            process.currentDirectoryURL = URL(fileURLWithPath: "/")
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            Log.app.error("Could not start the update script: \(String(describing: error), privacy: .private)")
            throw failure
        }
        Log.app.notice("Update verified; replacing \(target.appURL.path, privacy: .private) after quitting")
    }

    // MARK: Processes

    /// Runs a tool with no input or output and returns its exit status; stops it after
    /// `processTimeout` seconds.
    private static func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + processTimeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
            return -1
        }
        return process.terminationStatus
    }
}
