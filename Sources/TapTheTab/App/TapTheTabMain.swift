import AppKit

@main
enum TapTheTabMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let flagIndex = arguments.firstIndex(of: "--render-screenshots") {
            renderScreenshots(arguments: arguments, flagIndex: flagIndex)
        }
        if let code = RescueCommands.run(arguments) {
            exit(code)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu-bar agent: no Dock icon, no main menu. (Info.plist sets LSUIElement too.)
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    /// Hidden mode for the README screenshots (`make screenshots`, CI):
    /// `TapTheTab --render-screenshots <directory>` draws the switcher and Settings from
    /// built-in sample data into PNG files, prints their paths and exits. None of the app
    /// starts: no event tap, menu bar item, config file, window list or permission prompt.
    @MainActor
    private static func renderScreenshots(arguments: [String], flagIndex: Int) -> Never {
        let pathIndex = flagIndex + 1
        guard pathIndex < arguments.count, !arguments[pathIndex].hasPrefix("-") else {
            FileHandle.standardError.write(Data("usage: TapTheTab --render-screenshots <output directory>\n".utf8))
            exit(2)
        }
        let directory = URL(fileURLWithPath: arguments[pathIndex], isDirectory: true)

        // Needed for windows and AppKit drawing; never run, never activated.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let result = ScreenshotRenderer.renderAll(to: directory)
        for url in result.written {
            print(url.path)
        }
        for failure in result.failures {
            FileHandle.standardError.write(Data("error: \(failure)\n".utf8))
        }
        let succeeded = result.failures.isEmpty && !result.written.isEmpty
        exit(succeeded ? 0 : 1)
    }
}
