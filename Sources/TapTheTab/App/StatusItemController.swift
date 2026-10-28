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

    /// Hidden on request; opening the app again (or tapthetab://settings) shows Settings.
    func setVisible(_ visible: Bool) {
        if statusItem.isVisible != visible { statusItem.isVisible = visible }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !actions.accessibilityGranted() {
            let warning = item(L10n.tr("Accessibility permission needed…"), #selector(showPermissions))
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let show = item(L10n.tr("Show Switcher"), #selector(showSwitcher))
        show.isEnabled = actions.accessibilityGranted() && !actions.isPaused()
        menu.addItem(show)
        menu.addItem(item(actions.isPaused() ? L10n.tr("Resume TapTheTab") : L10n.tr("Pause TapTheTab"), #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(item(L10n.tr("Settings…"), #selector(showSettings), key: ","))
        menu.addItem(item(L10n.tr("Permissions…"), #selector(showPermissions)))
        menu.addItem(.separator())
        let version = NSMenuItem(title: "TapTheTab \(AppInfo.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(item(L10n.tr("Check for Updates…"), #selector(checkForUpdates)))
        menu.addItem(item(L10n.tr("Quit TapTheTab"), #selector(quit), key: "q"))
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

    /// Opens the releases page in the browser. TapTheTab itself never goes online.
    @objc private func checkForUpdates() { NSWorkspace.shared.open(AppInfo.releasesURL) }
}
