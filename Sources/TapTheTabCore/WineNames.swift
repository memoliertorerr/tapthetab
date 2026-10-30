import Foundation

/// Readable names for Windows programs run by Wine, CrossOver, Whisky or Apple's Game
/// Porting Toolkit. Each .exe runs as its own macOS process, but that process is the Wine
/// loader, so the system reports it as "wine64-preloader" or similar for every program.
/// The program's own name is in the process arguments (see docs/research/vm-windows.md).
public enum WineNames {
    /// Loader executable names, lowercased: Wine's own (wine, wine64, their preloaders,
    /// wineloader), CrossOver's 32-on-64 builds, and the 16-character forms the kernel
    /// keeps of longer names (`p_comm`).
    static let loaderNames: Set<String> = [
        "wine", "wine64", "wine32", "wine32on64",
        "wine-preloader", "wine64-preloader", "wine32-preloader", "wine32on64-preloader",
        "wineloader", "wineloader64", "wineloader32",
        "wine32on64-prelo", // "wine32on64-preloader" cut to 16 characters
    ]

    /// Programs that only start another program, whose name is the one to show:
    /// `start [/unix] x.exe`, `cmd /c x.exe`, `explorer /desktop=… x.exe`, the console
    /// host and the 16-bit runner.
    static let launcherNames: Set<String> = [
        "start", "cmd", "explorer", "conhost", "wineconsole", "winevdm",
    ]

    /// How many arguments are looked at, and the longest argument considered.
    static let maximumArguments = 64
    static let maximumArgumentLength = 4096
    /// Longest name returned; longer file names are not used.
    static let maximumNameLength = 80

    /// True for process or app names of Wine loaders, compared case-insensitively, given
    /// as a bare name or a path ("/…/CrossOver/lib/wine/x86_64-unix/wine64-preloader").
    /// False for Wine's helper processes such as wineserver, which own no windows.
    public static func isWineLoader(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumArgumentLength else { return false }
        let last = trimmed.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? trimmed
        return loaderNames.contains(last.lowercased())
    }

    /// A readable app name from the process's arguments (argv[0]… as KERN_PROCARGS2
    /// returns them): the file name, without ".exe", of the first argument that is a
    /// Windows executable ("C:\\Program Files\\Notepad++\\notepad++.exe" → "notepad++").
    ///
    /// Takes Windows paths ("\\" or "/" separators, drive letters such as "Z:"), Unix paths
    /// and bare names, quoted or not, and an argument holding a whole command line
    /// ("\"C:\\A B\\app.exe\" -flag"). Skips the loader, flags, other arguments that are
    /// not .exe files (`/unix`, `/desktop=…`, `--bottle`, .lnk shortcuts) and launchers
    /// (start, cmd, explorer, …) that are followed by the real program. nil when no
    /// usable name is found; never an empty or path-like string.
    public static func displayName(fromArguments arguments: [String]) -> String? {
        for argument in arguments.prefix(maximumArguments) where argument.utf8.count <= maximumArgumentLength {
            for path in executablePaths(in: argument) {
                guard let name = fileName(of: path), !launcherNames.contains(name.lowercased()) else { continue }
                return name
            }
        }
        return nil
    }

    /// The .exe paths an argument names, in order. Usually the whole argument is one path
    /// (spaces included, as in "C:\\Program Files\\App\\app.exe"); an argument can also
    /// hold a command line such as "explorer.exe /desktop=shell \"C:\\A B\\app.exe\" -x",
    /// where each quoted or unquoted ".exe" counts, without the switches before it.
    static func executablePaths(in argument: String) -> [String] {
        var paths: [String] = []
        var rest = Substring(argument.trimmingCharacters(in: .whitespacesAndNewlines))
        while !rest.isEmpty, paths.count < 8 {
            rest = rest.drop(while: { $0.isWhitespace })
            if let quote = rest.first, quote == "\"" || quote == "'" {
                let inner = rest.dropFirst()
                let end = inner.firstIndex(of: quote) ?? inner.endIndex
                let token = inner[..<end].trimmingCharacters(in: .whitespaces)
                if token.lowercased().hasSuffix(".exe") { paths.append(token) }
                rest = end < inner.endIndex ? inner[inner.index(after: end)...] : ""
                continue
            }
            // The text up to the next ".exe" that ends a word, without leading switches.
            guard let end = Self.endOfExe(in: rest) else { break }
            if let path = Self.pathPart(of: rest[..<end]) { paths.append(path) }
            rest = rest[end...]
        }
        return paths
    }

    /// Where the path starts in "[switches] [launcher] path.exe": leading switches
    /// ("-x", "--bottle", "/unix", "/desktop=…", "/c"), launcher and loader words
    /// ("start", "wine64") are dropped; then the text from the first Windows drive or
    /// Unix path, or else all that is left (a bare name, which may contain spaces).
    private static func pathPart(of segment: Substring) -> String? {
        var text = segment.drop(while: { $0.isWhitespace })
        while let tokenEnd = text.firstIndex(where: { $0.isWhitespace }) {
            let token = text[..<tokenEnd]
            let lower = token.lowercased()
            let isSwitch = token.hasPrefix("-")
                || (token.hasPrefix("/") && !token.dropFirst().contains(where: { $0 == "/" || $0 == "\\" }))
            guard isSwitch || launcherNames.contains(lower) || loaderNames.contains(lower) else { break }
            text = text[tokenEnd...].drop(while: { $0.isWhitespace })
        }
        if text.hasPrefix("-") { return nil }
        // A path that starts later, after words that belong to no path ("--bottle Steam C:\…").
        if !startsPath(text) {
            var index = text.startIndex
            while let space = text[index...].firstIndex(where: { $0.isWhitespace }) {
                let next = text.index(after: space)
                if next < text.endIndex, startsPath(text[next...]) {
                    text = text[next...]
                    break
                }
                index = next
            }
        }
        return text.isEmpty ? nil : String(text)
    }

    /// "C:\\…", "C:/…", "\\\\server\\…", or a Unix path with at least two components
    /// in its first word ("/Users/me/…").
    private static func startsPath(_ text: Substring) -> Bool {
        let chars = Array(text.prefix(3))
        if chars.count == 3, chars[0].isASCII, chars[0].isLetter, chars[1] == ":", chars[2] == "\\" || chars[2] == "/" {
            return true
        }
        if text.hasPrefix("\\\\") { return true }
        if text.hasPrefix("/") {
            let word = text.prefix(while: { !$0.isWhitespace })
            return word.dropFirst().contains("/")
        }
        return false
    }

    /// The index just after the first ".exe" (any case) followed by whitespace, a quote
    /// or the end of `text`.
    private static func endOfExe(in text: Substring) -> Substring.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            guard let range = text[index...].range(of: ".exe", options: .caseInsensitive) else { return nil }
            let after = range.upperBound
            if after == text.endIndex || text[after].isWhitespace || text[after] == "\"" || text[after] == "'" {
                return after
            }
            index = after
        }
        return nil
    }

    /// The file name of a Windows or Unix path without its ".exe", or nil when nothing
    /// readable is left.
    static func fileName(of path: String) -> String? {
        let last = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? ""
        // Drive-relative paths ("C:app.exe") keep their drive letter in the last part.
        let afterDrive = last.split(separator: ":", omittingEmptySubsequences: false).last.map(String.init) ?? last
        guard afterDrive.lowercased().hasSuffix(".exe") else { return nil }
        let name = String(afterDrive.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameLength,
              name.contains(where: { $0.isLetter || $0.isNumber }),
              !name.unicodeScalars.contains(where: {
                  $0 == "/" || $0 == "\\" || $0 == ":" || $0 == "\"" || $0 == "*" || $0 == "?" || $0 == "<" || $0 == ">" || $0 == "|"
                      || $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
              })
        else { return nil }
        return name
    }
}
