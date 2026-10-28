import XCTest
@testable import TapTheTabCore

final class ConfigStoreTests: XCTestCase {
    private var directory: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        directory = fm.temporaryDirectory.appendingPathComponent("TapTheTabTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory, fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
    }

    private var store: ConfigStore { ConfigStore(directory: directory) }

    private func write(_ text: String) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: store.fileURL)
    }

    private func readFile() throws -> String {
        String(decoding: try Data(contentsOf: store.fileURL), as: UTF8.self)
    }

    private func permissions(_ path: String) throws -> Int {
        let attrs = try fm.attributesOfItem(atPath: path)
        return try XCTUnwrap((attrs[.posixPermissions] as? NSNumber)?.intValue)
    }

    private func quarantinedFiles() throws -> [String] {
        try fm.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("config.invalid-") }.sorted()
    }

    // MARK: -

    func testFileURL() {
        XCTAssertEqual(store.fileURL.lastPathComponent, "config.json")
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
    }

    func testDefaultDirectoryEndsWithAppName() {
        XCTAssertEqual(ConfigStore.defaultDirectory().lastPathComponent, "TapTheTab")
    }

    func testMissingFileWritesDefaults() throws {
        let result = store.load()
        XCTAssertEqual(result.configuration, Configuration())
        XCTAssertTrue(result.createdDefaultFile)
        XCTAssertNil(result.quarantinedFile)
        XCTAssertEqual(result.notes, [])
        XCTAssertTrue(fm.fileExists(atPath: store.fileURL.path))
        let onDisk = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: store.fileURL))
        XCTAssertEqual(onDisk, Configuration())
    }

    func testSecondLoadReadsTheCreatedFile() {
        _ = store.load()
        let result = store.load()
        XCTAssertFalse(result.createdDefaultFile)
        XCTAssertEqual(result.configuration, Configuration())
    }

    func testValidFileLoads() throws {
        try write(#"{"appearance": {"style": "list"}, "behavior": {"searchEnabled": false}}"#)
        let result = store.load()
        var expected = Configuration()
        expected.appearance.style = .list
        expected.behavior.searchEnabled = false
        XCTAssertEqual(result.configuration, expected)
        XCTAssertFalse(result.createdDefaultFile)
        XCTAssertNil(result.quarantinedFile)
        XCTAssertEqual(result.notes, [])
    }

    func testLoadValidatesAndReportsNotes() throws {
        try write(#"{"appearance": {"showDelayMilliseconds": 99999}, "triggers": [{"shortcut": "tab", "scope": "apps"}]}"#)
        let result = store.load()
        XCTAssertEqual(result.configuration.appearance.showDelayMilliseconds, 1000)
        XCTAssertEqual(result.configuration.triggers, Configuration.defaultTriggers)
        XCTAssertEqual(result.notes.count, 3)
        XCTAssertNil(result.quarantinedFile)
    }

    func testLoadDoesNotRewriteAValidFile() throws {
        let text = #"{"appearance": {"theme": "dark"}}"#
        try write(text)
        _ = store.load()
        XCTAssertEqual(try readFile(), text)
    }

    func testCorruptFileIsQuarantinedAndReplaced() throws {
        let garbage = "{ this is not json"
        try write(garbage)
        let result = store.load()

        XCTAssertEqual(result.configuration, Configuration())
        XCTAssertFalse(result.createdDefaultFile)
        let aside = try XCTUnwrap(result.quarantinedFile)
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("config.invalid-"))
        XCTAssertEqual(aside.pathExtension, "json")
        XCTAssertTrue(fm.fileExists(atPath: aside.path))
        XCTAssertEqual(String(decoding: try Data(contentsOf: aside), as: UTF8.self), garbage, "the user's file is kept byte for byte")
        XCTAssertEqual(result.notes.count, 2)

        // The original location now holds a fresh, valid default file.
        let onDisk = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: store.fileURL))
        XCTAssertEqual(onDisk, Configuration())
    }

    func testWrongValueKeepsFileAndOtherSettings() throws {
        try write(#"{"behavior": {"wrapAround": "yes", "searchEnabled": false}}"#)
        let result = store.load()
        XCTAssertNil(result.quarantinedFile, "a single bad value must not discard the user's file")
        XCTAssertFalse(result.configuration.behavior.searchEnabled)
        XCTAssertTrue(result.configuration.behavior.wrapAround)
        XCTAssertTrue(try quarantinedFiles().isEmpty)
    }

    func testSaveLeavesNoTemporaryFiles() throws {
        try store.save(Configuration())
        try store.save(Configuration())
        let names = try fm.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path)
        XCTAssertEqual(names, ["config.json"])
    }

    func testEmptyFileIsQuarantined() throws {
        try write("")
        let result = store.load()
        XCTAssertNotNil(result.quarantinedFile)
        XCTAssertEqual(result.configuration, Configuration())
    }

    func testRepeatedCorruptionDoesNotOverwriteEarlierQuarantine() throws {
        // Two broken files within the same second must both be kept.
        try write("broken one")
        let first = try XCTUnwrap(store.load().quarantinedFile)
        try write("broken two")
        let second = try XCTUnwrap(store.load().quarantinedFile)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(String(decoding: try Data(contentsOf: first), as: UTF8.self), "broken one")
        XCTAssertEqual(String(decoding: try Data(contentsOf: second), as: UTF8.self), "broken two")
        XCTAssertEqual(try quarantinedFiles().count, 2)
        XCTAssertNoThrow(try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: store.fileURL)))
    }

    func testSaveWritesPrettySortedJSON() throws {
        var c = Configuration()
        c.filters.excludedBundleIDs = ["com.example/slash"]
        try store.save(c)
        let text = try readFile()
        XCTAssertTrue(text.contains("\n"), "pretty-printed")
        XCTAssertTrue(text.contains("com.example/slash"), "slashes are not escaped")
        let appearance = try XCTUnwrap(text.range(of: "\"appearance\""))
        let version = try XCTUnwrap(text.range(of: "\"version\""))
        XCTAssertLessThan(appearance.lowerBound, version.lowerBound, "keys are sorted")
        XCTAssertEqual(store.load().configuration, c)
    }

    func testSaveCreatesMissingDirectories() throws {
        let nested = directory.appendingPathComponent("a/b", isDirectory: true)
        let store = ConfigStore(directory: nested)
        try store.save(Configuration())
        XCTAssertTrue(fm.fileExists(atPath: store.fileURL.path))
    }

    func testSaveOverwrites() throws {
        var c = Configuration()
        c.appearance.theme = .light
        try store.save(c)
        c.appearance.theme = .dark
        try store.save(c)
        XCTAssertEqual(store.load().configuration.appearance.theme, .dark)
    }

    func testFilePermissionsAreOwnerOnly() throws {
        try store.save(Configuration())
        XCTAssertEqual(try permissions(store.fileURL.path), 0o600)
        XCTAssertEqual(try permissions(directory.path) & 0o777, 0o700)
    }

    func testDefaultFileFromLoadIsOwnerOnly() throws {
        _ = store.load()
        XCTAssertEqual(try permissions(store.fileURL.path), 0o600)
    }

    func testUnwritableDirectoryReportsNote() throws {
        // A regular file where the directory should be makes creation fail.
        let blocker = directory!
        try fm.createDirectory(at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker)
        let result = ConfigStore(directory: blocker).load()
        XCTAssertEqual(result.configuration, Configuration())
        XCTAssertFalse(result.createdDefaultFile)
        XCTAssertEqual(result.notes.count, 1)
    }
}
