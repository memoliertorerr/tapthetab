import Foundation

/// A command received through a `tapthetab://` URL, for launchers and automation
/// (Raycast, Alfred, Shortcuts, `open tapthetab://switch`).
///
/// Any app or web page can open a URL, so this is a parser for untrusted input: it is
/// strict, bounded, and can only express harmless commands that open TapTheTab's own UI.
/// Nothing that closes, quits, minimizes or otherwise changes another app is reachable
/// from a URL, and none must ever be added.
///
/// Accepted forms (the command name and the scheme are case-insensitive):
/// - `tapthetab://switch`, `tapthetab://switch/`, `tapthetab:switch`, `tapthetab:///switch`
/// - `…switch?scope=allWindows|activeApp|apps&query=text` (both parameters optional)
/// - `tapthetab://settings` (same forms; parameters are ignored)
///
/// Rules:
/// - a user, password or port in the URL makes it invalid; a fragment is ignored;
/// - parameter names are case-sensitive; unknown parameters are ignored; for a repeated
///   `scope` or `query` the first one wins;
/// - `scope` values are matched case-insensitively; an unknown or empty `scope` makes the
///   whole URL invalid rather than guessing;
/// - `+` is a literal plus (RFC 3986), not a space; use `%20` for spaces;
/// - malformed percent-encoding (including bytes that are not UTF-8) anywhere in the query
///   makes the whole URL invalid;
/// - the query text has control characters, line/paragraph separators and bidirectional
///   formatting characters removed, is trimmed, truncated to `maximumQueryLength`
///   characters, and becomes nil when nothing is left.
public enum AutomationCommand: Equatable, Sendable {
    /// Open the switcher, locked open (no modifier to release), optionally pre-filtered.
    case showSwitcher(scope: SwitcherScope, query: String?)
    case openSettings

    public static let scheme = "tapthetab"
    /// Longest pre-filled query, in Characters (grapheme clusters).
    public static let maximumQueryLength = 200

    /// Parses `tapthetab://switch[?scope=…][&query=…]` and `tapthetab://settings`.
    /// Returns nil for anything else (wrong scheme, unknown host/path, unknown scope,
    /// bad encoding, credentials or port).
    public init?(url: URL) {
        guard let scheme = url.scheme, scheme.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              let name = Self.commandName(host: components.host, path: components.path),
              let parameters = Self.parameters(percentEncodedQuery: components.percentEncodedQuery)
        else { return nil }

        switch name {
        case "switch":
            var scope = SwitcherScope.allWindows
            if let raw = parameters.first(where: { $0.name == "scope" })?.value {
                guard let parsed = SwitcherScope.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) else {
                    return nil
                }
                scope = parsed
            }
            let query = parameters.first(where: { $0.name == "query" }).flatMap { Self.sanitizedQuery($0.value) }
            self = .showSwitcher(scope: scope, query: query)
        case "settings":
            self = .openSettings
        default:
            return nil
        }
    }

    // MARK: - Private

    /// The lowercased command from the host (`tapthetab://switch`), or from the path when
    /// there is no host (`tapthetab:switch`, `tapthetab:///switch`).
    private static func commandName(host: String?, path: String) -> String? {
        let name: Substring
        if let host, !host.isEmpty {
            guard path.isEmpty || path == "/" else { return nil }
            name = Substring(host)
        } else {
            var trimmed = Substring(path)
            while trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
            if trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
            name = trimmed
        }
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return name.lowercased()
    }

    /// Splits and percent-decodes `a=1&b=2`. Returns nil when any name or value has
    /// malformed percent-encoding. A parameter without `=` has an empty value.
    private static func parameters(percentEncodedQuery: String?) -> [(name: String, value: String)]? {
        guard let query = percentEncodedQuery, !query.isEmpty else { return [] }
        var result: [(name: String, value: String)] = []
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = String(parts[0]).removingPercentEncoding else { return nil }
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            guard let value = rawValue.removingPercentEncoding else { return nil }
            result.append((name, value))
        }
        return result
    }

    /// Unicode scalars that never belong in a search query: C0/C1 controls (newlines,
    /// tabs, NUL, DEL), line/paragraph separators and bidirectional formatting characters.
    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F: return true      // C0 and C1 controls, DEL
        case 0x2028, 0x2029: return true                 // line / paragraph separator
        case 0x200E, 0x200F, 0x061C: return true         // LRM, RLM, ALM
        case 0x202A...0x202E: return true                // LRE, RLE, PDF, LRO, RLO
        case 0x2066...0x2069: return true                // LRI, RLI, FSI, PDI
        default: return false
        }
    }

    private static func sanitizedQuery(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: raw.unicodeScalars.lazy.filter { !isForbidden($0) })
        let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        let bounded = String(cleaned.prefix(maximumQueryLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.isEmpty ? nil : bounded
    }
}
