import AppKit

@main
enum TapTheTabMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu-bar agent: no Dock icon, no main menu. (Info.plist sets LSUIElement too.)
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
