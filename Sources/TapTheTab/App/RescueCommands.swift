import AppKit
import TapTheTabCore

/// Command-line rescue tools, for when something is wrong and the app itself can't help:
///
///     /Applications/TapTheTab.app/Contents/MacOS/TapTheTab --restore-system-shortcuts
///     /Applications/TapTheTab.app/Contents/MacOS/TapTheTab --reset-settings
///
/// They run instead of the app and exit; nothing else starts.
enum RescueCommands {
    static let usage = """
    usage: TapTheTab [option]

      --restore-system-shortcuts  Turn macOS's own ⌘⇥ / ⌘⇧⇥ / ⌘` back on (if they stayed
                                  off after TapTheTab crashed or was removed while running).
      --reset-settings            Move config.json aside (it is kept, renamed) and forget
                                  TapTheTab's other saved state. The next launch uses defaults.
      --version                   Print the version.
      --help                      Show this help.
      --render-screenshots <dir>  Draw the README screenshots from sample data (for developers).
      --render-demo <file.png>    Draw the demo animation (animated PNG) from sample data.

    Quit TapTheTab before using these.
    """

    /// Exit code when an option was handled, nil to launch the app normally.
    static func run(_ arguments: [String]) -> Int32? {
        let options = Array(arguments.dropFirst())
        guard let option = options.first, option.hasPrefix("-") else { return nil }
        switch option {
        case "--restore-system-shortcuts":
            return restoreSystemShortcuts()
        case "--reset-settings":
            return resetSettings()
        case "--version":
            print("TapTheTab \(AppInfo.version) (\(AppInfo.build))")
            return 0
        case "--help", "-h":
            print(usage)
            return 0
        default:
            // Launch Services may pass its own arguments (e.g. -psn_…, -NSDocumentRevisions…);
            // anything we don't know starts the app normally.
            return nil
        }
    }

    private static func restoreSystemShortcuts() -> Int32 {
        guard PrivateAPI.cgsSetSymbolicHotKeyEnabled != nil else {
            printError("This version of macOS doesn't expose the call needed; log out and back in to restore ⌘⇥.")
            return 1
        }
        for hotkey in SymbolicHotkey.allCases { hotkey.setEnabled(true) }
        UserDefaults.standard.removeObject(forKey: HotkeyMonitor.disabledHotkeysDefaultsKey)
        print("Restored the system shortcuts ⌘⇥, ⌘⇧⇥ and ⌘`.")
        return 0
    }

    private static func resetSettings() -> Int32 {
        let store = ConfigStore(directory: ConfigStore.defaultDirectory())
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: store.fileURL.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = store.fileURL.deletingLastPathComponent().appendingPathComponent("config.before-reset-\(stamp).json")
            do {
                try fileManager.moveItem(at: store.fileURL, to: aside)
                print("Moved config.json to \(aside.path)")
            } catch {
                printError("Could not move config.json aside: \(error.localizedDescription)")
                return 1
            }
        } else {
            print("No config.json to reset.")
        }
        // Restore anything we may have switched off, then forget our saved state.
        for hotkey in SymbolicHotkey.allCases { hotkey.setEnabled(true) }
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        } else {
            UserDefaults.standard.removeObject(forKey: HotkeyMonitor.disabledHotkeysDefaultsKey)
        }
        print("Settings reset. The next launch starts with defaults.")
        return 0
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}
