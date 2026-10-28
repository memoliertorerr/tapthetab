import Foundation
import TapTheTabCore

/// Owns the live configuration, persists changes and notices hand edits of config.json.
/// Main-thread only.
final class ConfigurationController {
    let store: ConfigStore
    private(set) var configuration: Configuration
    /// Called on the main thread when config.json changed on disk and was re-read.
    var onExternalChange: ((Configuration) -> Void)?

    private var watcher: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?

    init(store: ConfigStore) {
        self.store = store
        let result = store.load()
        configuration = result.configuration
        for note in result.notes { Log.config.notice("\(note, privacy: .public)") }
    }

    /// Validates, saves and returns the configuration actually in effect.
    @discardableResult
    func update(_ newValue: Configuration) -> Configuration {
        let (valid, notes) = newValue.validated()
        for note in notes { Log.config.notice("\(note, privacy: .public)") }
        guard valid != configuration else { return valid }
        configuration = valid
        do {
            try store.save(valid)
        } catch {
            Log.config.error("Saving config failed: \(error.localizedDescription, privacy: .public)")
        }
        return valid
    }

    /// Watches the config directory (saves are atomic renames, so the file itself is replaced).
    func startWatching() {
        let directory = store.fileURL.deletingLastPathComponent()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func scheduleReload() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadFromDisk() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func reloadFromDisk() {
        // Editors save in steps; a half-written or mistyped file must not reset settings
        // or be moved aside while the app runs. Keep the current settings until it parses.
        guard let result = store.readIfValid() else {
            Log.config.notice("config.json is missing or not valid right now; keeping current settings")
            return
        }
        for note in result.notes { Log.config.notice("\(note, privacy: .public)") }
        guard result.configuration != configuration else { return }
        configuration = result.configuration
        Log.config.info("config.json changed on disk; reloaded")
        onExternalChange?(result.configuration)
    }
}
