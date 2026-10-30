import Foundation

// Opt-in update checks (`Behavior.checkForUpdates`, off by default). The core only
// decides: which versions are newer, what a GitHub release response means, whether a
// check is due. The app does the request and shows the result. It downloads and installs
// an update only when the user clicks Install and Relaunch, never on its own.

/// A release version like "0.10.0", "v1.2.3" or "1.0.0-beta.2", ordered by SemVer 2.0
/// precedence: numeric parts compared numerically, a prerelease below its release,
/// prerelease identifiers compared one by one (numeric ones numerically and below
/// alphanumeric ones), and a shorter list of equal identifiers lower. Build metadata
/// ("+…") is accepted and ignored, so it never affects equality or order.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int, minor: Int, patch: Int
    /// Dot-separated prerelease identifiers ("beta", "2"); empty for a release.
    public let prerelease: [String]

    /// Longest string accepted; real versions are far shorter. Bounds hostile input.
    static let maximumLength = 64

    /// Accepts an optional leading "v"/"V", one to three numeric parts ("1.2" is 1.2.0),
    /// an optional "-prerelease" and an optional "+build" (ignored). Surrounding
    /// whitespace is ignored. nil for anything else, including leading zeros ("01.2.3",
    /// "1.0.0-beta.02"), empty parts, negative or overflowing numbers and non-ASCII.
    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty, text.utf8.count <= Self.maximumLength, text.allSatisfy(\.isASCII) else { return nil }
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }

        if let plus = text.firstIndex(of: "+") {
            let build = text[text.index(after: plus)...]
            guard Self.validIdentifiers(build, numericLeadingZerosAllowed: true) != nil else { return nil }
            text = text[..<plus]
        }
        var prerelease: [String] = []
        if let dash = text.firstIndex(of: "-") {
            let pre = text[text.index(after: dash)...]
            guard let identifiers = Self.validIdentifiers(pre, numericLeadingZerosAllowed: false) else { return nil }
            prerelease = identifiers
            text = text[..<dash]
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard Self.isNumeric(part), part == "0" || part.first != "0", let value = Int(part) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        self.prerelease = prerelease
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// "0.10.0", "1.0.0-beta.2" (no "v", no build metadata).
    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // A release ranks above any of its prereleases.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true), (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            return identifierPrecedes(a, b)
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    /// SemVer rule 11.4 for two different identifiers.
    private static func identifierPrecedes(_ a: String, _ b: String) -> Bool {
        switch (isNumeric(Substring(a)), isNumeric(Substring(b))) {
        case (true, true):
            // No leading zeros, so a longer digit string is a larger number; comparing
            // this way never overflows.
            return a.count != b.count ? a.count < b.count : a < b
        case (true, false): return true
        case (false, true): return false
        case (false, false): return Array(a.utf8).lexicographicallyPrecedes(Array(b.utf8))
        }
    }

    private static func isNumeric(_ s: Substring) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    /// Dot-separated, non-empty identifiers of [0-9A-Za-z-]; nil when any is invalid.
    private static func validIdentifiers(_ s: Substring, numericLeadingZerosAllowed: Bool) -> [String]? {
        let identifiers = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return nil }
        for identifier in identifiers {
            guard !identifier.isEmpty, identifier.utf8.allSatisfy({ byte in
                (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2D
            }) else { return nil }
            if !numericLeadingZerosAllowed, isNumeric(identifier), identifier.count > 1, identifier.first == "0" {
                return nil
            }
        }
        return identifiers.map(String.init)
    }
}

/// What the app needs from a GitHub release.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: AppVersion
    /// The tag as GitHub returned it ("v0.10.0").
    public var tag: String
    /// The release's page (`html_url`), always under the project's releases on github.com.
    public var pageURL: URL
    /// Download URL of "TapTheTab-<version>.dmg", if the release has it at a trusted URL.
    public var dmgURL: URL?
    /// Download URL of "SHA256SUMS.txt", if the release has it at a trusted URL.
    public var checksumsURL: URL?
    /// Release notes (Markdown `body`), possibly empty; at most
    /// `ReleaseFeed.maximumNotesLength` characters.
    public var notes: String
    public var isPrerelease: Bool

    public init(
        version: AppVersion,
        tag: String,
        pageURL: URL,
        dmgURL: URL? = nil,
        checksumsURL: URL? = nil,
        notes: String = "",
        isPrerelease: Bool = false
    ) {
        self.version = version
        self.tag = tag
        self.pageURL = pageURL
        self.dmgURL = dmgURL
        self.checksumsURL = checksumsURL
        self.notes = notes
        self.isPrerelease = isPrerelease
    }
}

/// The project's GitHub releases, read from the public REST API (no token, no account).
public enum ReleaseFeed {
    static let owner = "memoliertorerr"
    static let repository = "tapthetab"

    /// https://api.github.com/repos/memoliertorerr/tapthetab/releases/latest
    public static let latestURL = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
    /// https://github.com/memoliertorerr/tapthetab/releases
    public static let releasesPageURL = URL(string: "https://github.com/\(owner)/\(repository)/releases")!

    /// Responses larger than this are not parsed (the app should stop reading there).
    /// A real "latest release" response is a few kilobytes.
    public static let maximumResponseBytes = 2 * 1024 * 1024
    /// Longer release notes are cut to this many characters.
    public static let maximumNotesLength = 20_000
    /// Name of the checksums asset written by `scripts/package.sh`.
    public static let checksumsName = "SHA256SUMS.txt"

    /// "TapTheTab-0.10.0.dmg", as `scripts/package.sh` names it.
    public static func dmgName(for version: AppVersion) -> String {
        "TapTheTab-\(version.description).dmg"
    }

    private struct Response: Decodable {
        var tagName: String
        var htmlURL: String
        var draft: Bool
        var prerelease: Bool
        var body: String?
        var assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, body, assets
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tagName = try c.decode(String.self, forKey: .tagName)
            htmlURL = try c.decode(String.self, forKey: .htmlURL)
            // Missing flags read as false (GitHub always sends them); a wrong type fails.
            draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
            prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
            body = c.lenient(String.self, .body)
            assets = c.lenientArray(Asset.self, .assets) ?? []
        }
    }

    private struct Asset: Decodable {
        var name: String
        var url: String
        enum CodingKeys: String, CodingKey { case name, url = "browser_download_url" }
    }

    /// Parses GitHub's "latest release" JSON. nil for drafts, prereleases (flagged, or a
    /// prerelease version in the tag), tags that are not versions, a missing or untrusted
    /// `html_url` (it must be https://github.com/memoliertorerr/tapthetab/releases/…),
    /// oversized input and anything that is not such a JSON object.
    ///
    /// Assets are found by exact name (`dmgName(for:)` of the tag's version and
    /// "SHA256SUMS.txt"). An asset URL is kept only when it is https on github.com (under
    /// this project's releases), objects.githubusercontent.com or another
    /// *.githubusercontent.com host, without user info or a non-default port; otherwise
    /// that asset is nil and the rest of the release still counts.
    public static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard !data.isEmpty, data.count <= maximumResponseBytes,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              !response.draft, !response.prerelease,
              let version = AppVersion(response.tagName), !version.isPrerelease,
              let page = trustedURL(response.htmlURL, kind: .page)
        else { return nil }

        func asset(named name: String) -> URL? {
            guard let asset = response.assets.first(where: { $0.name == name }) else { return nil }
            return trustedURL(asset.url, kind: .asset)
        }
        let notes = response.body ?? ""
        return ReleaseInfo(
            version: version,
            tag: response.tagName,
            pageURL: page,
            dmgURL: asset(named: dmgName(for: version)),
            checksumsURL: asset(named: checksumsName),
            notes: notes.count > maximumNotesLength ? String(notes.prefix(maximumNotesLength)) : notes,
            isPrerelease: false
        )
    }

    enum URLKind { case page, asset }

    /// The URL when it is one the app may open or download from; nil otherwise. Checks
    /// the raw text as well as the parsed URL, so no parser quirk (user info, backslashes,
    /// odd ports, encoded dots) can point it somewhere else.
    static func trustedURL(_ string: String, kind: URLKind) -> URL? {
        let prefix = "https://"
        guard string.utf8.count <= 2048,
              string.lowercased().hasPrefix(prefix),
              string.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F && $0 != "\\" })
        else { return nil }
        let rest = string.dropFirst(prefix.count)
        let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let host = rest[..<authorityEnd].lowercased()
        let pathAndMore = rest[authorityEnd...]
        let pathEnd = pathAndMore.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? pathAndMore.endIndex
        let path = String(pathAndMore[..<pathEnd])

        // Only letters, digits, dots and hyphens: no user info ("@"), no port (":").
        guard !host.isEmpty, host.utf8.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2E || $0 == 0x2D }),
              !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..")
        else { return nil }

        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard path.hasPrefix("/"), !path.contains("%"),
              !segments.contains(where: { $0 == "." || $0 == ".." })
        else { return nil }

        let projectReleases = "/\(owner)/\(repository)/releases/"
        let lowerPath = path.lowercased()
        switch kind {
        case .page:
            guard host == "github.com", lowerPath.hasPrefix(projectReleases), lowerPath.count > projectReleases.count else { return nil }
        case .asset:
            if host == "github.com" {
                guard lowerPath.hasPrefix(projectReleases + "download/") else { return nil }
            } else {
                let suffix = ".githubusercontent.com"
                guard host.hasSuffix(suffix), host.count > suffix.count, path.count > 1 else { return nil }
            }
        }

        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host,
              url.user == nil, url.password == nil, url.port == nil
        else { return nil }
        return url
    }
}

public enum Checksums {
    /// Reads `shasum -a 256` / `sha256sum` output into [file name: lowercase hex].
    ///
    /// Accepts "<64 hex>  <name>" (text mode), "<64 hex> *<name>" (binary mode) and the
    /// BSD form "SHA256 (<name>) = <64 hex>". Ignores blank and malformed lines, including
    /// sha256sum's escaped ("\…") lines. A name listed twice with different digests is
    /// dropped, since neither can be trusted.
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var conflicting = Set<String>()
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            guard let (name, hex) = entry(rawLine) else { continue }
            if let existing = result[name], existing != hex {
                conflicting.insert(name)
            }
            result[name] = hex
        }
        for name in conflicting { result[name] = nil }
        return result
    }

    private static func entry(_ rawLine: Substring) -> (String, String)? {
        var line = rawLine
        while let last = line.last, last.isWhitespace { line = line.dropLast() }
        guard !line.isEmpty else { return nil }

        // BSD / `shasum --tag`: SHA256 (name) = hex
        if line.hasPrefix("SHA256 ("), let close = line.range(of: ") = ", options: .backwards) {
            let name = line[line.index(line.startIndex, offsetBy: 8)..<close.lowerBound]
            let hex = line[close.upperBound...]
            return validated(name: name, hex: hex)
        }

        let chars = Array(line)
        guard chars.count > 66 else { return nil }
        let hex = String(chars[0..<64])
        guard chars[64] == " ", chars[65] == " " || chars[65] == "*" else { return nil }
        return validated(name: Substring(String(chars[66...])), hex: Substring(hex))
    }

    private static func validated(name: Substring, hex: Substring) -> (String, String)? {
        guard hex.count == 64, hex.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) || ($0 >= 0x41 && $0 <= 0x46) }),
              !name.isEmpty, !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return (String(name), hex.lowercased())
    }
}

public enum UpdatePolicy {
    /// Automatic checks run at most once a day.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Due when automatic checks are on and there was no check yet, the last one is at
    /// least `checkInterval` old, or it lies in the future (the clock was turned back).
    public static func isCheckDue(enabled: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    /// Offer `remote` only when it is a release (neither flagged nor versioned as a
    /// prerelease) and strictly newer than `current`. A prerelease build is offered its
    /// release ("1.0.0-beta.2" → "1.0.0").
    public static func shouldOffer(_ remote: ReleaseInfo, current: AppVersion) -> Bool {
        !remote.isPrerelease && !remote.version.isPrerelease && remote.version > current
    }
}
