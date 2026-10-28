import Foundation

/// Loads and saves `config.json`. Never throws away a file it cannot read: a broken
/// file is moved aside so the user can fix it, and defaults are used meanwhile.
public final class ConfigStore {
    public struct LoadResult: Equatable {
        public var configuration: Configuration
        public var notes: [String]
        public var createdDefaultFile: Bool
        /// Where an unreadable file was moved, if that happened.
        public var quarantinedFile: URL?
    }

    public let fileURL: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent("config.json")
        self.fileManager = fileManager
    }

    /// `~/Library/Application Support/TapTheTab` on macOS.
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TapTheTab", isDirectory: true)
    }

    public func load() -> LoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let config = Configuration()
            var notes: [String] = []
            do {
                try save(config)
            } catch {
                notes.append("Could not create \(fileURL.path): \(error.localizedDescription)")
            }
            return LoadResult(configuration: config, notes: notes, createdDefaultFile: notes.isEmpty, quarantinedFile: nil)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(Configuration.self, from: data)
            let (valid, notes) = decoded.validated()
            return LoadResult(configuration: valid, notes: notes, createdDefaultFile: false, quarantinedFile: nil)
        } catch {
            let aside = quarantineURL()
            var notes = ["config.json could not be read (\(Self.describe(error))). Using defaults."]
            var moved: URL?
            do {
                try fileManager.moveItem(at: fileURL, to: aside)
                moved = aside
                notes.append("The unreadable file was kept as \(aside.lastPathComponent).")
            } catch {
                notes.append("Could not move the unreadable file aside: \(error.localizedDescription)")
            }
            if moved != nil {
                do {
                    try save(Configuration())
                } catch {
                    notes.append("Could not write a fresh \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return LoadResult(configuration: Configuration(), notes: notes, createdDefaultFile: false, quarantinedFile: moved)
        }
    }

    /// A not-yet-existing `config.invalid-<unix time>[-n].json` next to the config file, so a
    /// second broken file in the same second never overwrites (or fails to move beside) the first.
    private func quarantineURL() -> URL {
        let directory = fileURL.deletingLastPathComponent()
        let stamp = Int(Date().timeIntervalSince1970)
        var candidate = directory.appendingPathComponent("config.invalid-\(stamp).json")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("config.invalid-\(stamp)-\(counter).json")
            counter += 1
        }
        return candidate
    }

    /// Writes atomically with owner-only permissions: the data goes to a 0600 temp file
    /// in the same 0700 directory, which is then renamed over config.json.
    public func save(_ configuration: Configuration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)

        let temp = directory.appendingPathComponent(".config.json.\(UUID().uuidString).tmp")
        guard fileManager.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temp.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
        guard rename(temp.path, fileURL.path) == 0 else {
            let code = errno
            try? fileManager.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path, NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(code))])
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let ctx):
            return ctx.debugDescription
        case DecodingError.typeMismatch(_, let ctx), DecodingError.valueNotFound(_, let ctx), DecodingError.keyNotFound(_, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? ctx.debugDescription : "\(path): \(ctx.debugDescription)"
        default:
            return error.localizedDescription
        }
    }
}
