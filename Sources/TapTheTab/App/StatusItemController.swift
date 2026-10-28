import AppKit

/// The menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var showSwitcher: () -> Void
        var togglePause: () -> Void
        var isPaused: () -> Bool
        var showSettings: () -> Void
        var showPermissions: () -> Void
        var accessibilityGranted: () -> Bool
    }

    private let statusItem: NSStatusItem
    private let actions: Actions
    private let menu = NSMenu()

    init(actions: Actions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "TapTheTab")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "TapTheTab"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !actions.accessibilityGranted() {
            let warning = item("Accessibility permission needed…", #selector(showPermissions))
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let show = item("Show Switcher", #selector(showSwitcher))
        show.isEnabled = actions.accessibilityGranted() && !actions.isPaused()
        menu.addItem(show)
        menu.addItem(item(actions.isPaused() ? "Resume TapTheTab" : "Pause TapTheTab", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Permissions…", #selector(showPermissions)))
        menu.addItem(.separator())
        let version = NSMenuItem(title: "TapTheTab \(AppInfo.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(item("Quit TapTheTab", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showSwitcher() {
        // Let the menu finish closing before the panel appears.
        DispatchQueue.main.async { [actions] in actions.showSwitcher() }
    }

    @objc private func togglePause() { actions.togglePause() }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func showPermissions() { actions.showPermissions() }
    @objc private func quit() { NSApp.terminate(nil) }
}
