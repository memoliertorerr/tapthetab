import AppKit
import TapTheTabCore

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
    /// What the current icon was drawn for, so unchanged settings do not redraw it.
    private var iconKey: MenuBarIcon.Key?

    init(actions: Actions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.toolTip = "TapTheTab"
        }
        setIconStyle(.classic, theme: ColorTheme.none)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// Redraws the icon in `style`; `theme` gives the themed icon its color (classic when the
    /// theme is off). Does nothing when neither changed what the icon looks like.
    func setIconStyle(_ style: MenuBarIconStyle, theme: ColorTheme) {
        let key = MenuBarIcon.Key(style: style, theme: theme)
        guard key != iconKey, let button = statusItem.button else { return }
        iconKey = key
        button.image = MenuBarIcon.image(for: style, theme: theme)
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

/// The menu bar icon in each `MenuBarIconStyle`. Also drawn small in Settings to pick one.
/// Template images (they follow a light or dark menu bar) except the themed one.
enum MenuBarIcon {
    /// What an icon depends on: the style, and for the themed one the color it is drawn in.
    struct Key: Equatable {
        let style: MenuBarIconStyle
        let color: SRGBColor?

        init(style: MenuBarIconStyle, theme: ColorTheme) {
            self.style = style
            color = style == .themed ? MenuBarIcon.themeColor(theme) : nil
        }
    }

    private static let classicSymbol = "rectangle.on.rectangle"
    private static let filledSymbol = "rectangle.fill.on.rectangle.fill"
    private static let accessibilityDescription = "TapTheTab"

    static func image(for style: MenuBarIconStyle, theme: ColorTheme) -> NSImage {
        switch style {
        case .classic:
            return symbol(classicSymbol)
        case .filled:
            return symbol(filledSymbol)
        case .minimal:
            return minimal()
        case .themed:
            guard let color = themeColor(theme) else { return symbol(classicSymbol) }
            return tinted(color)
        }
    }

    /// The theme's first color, or nil when the theme is off.
    static func themeColor(_ theme: ColorTheme) -> SRGBColor? {
        guard theme.isEnabled, let hex = theme.colors.first else { return nil }
        return SRGBColor(hex: hex)
    }

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
            ?? minimal()
        image.isTemplate = true
        return image
    }

    /// The classic shape in the theme's color: not a template, so it keeps the color.
    private static func tinted(_ color: SRGBColor) -> NSImage {
        let nsColor = NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
        let configuration = NSImage.SymbolConfiguration(paletteColors: [nsColor])
        guard let base = NSImage(systemSymbolName: classicSymbol, accessibilityDescription: accessibilityDescription),
              let image = base.withSymbolConfiguration(configuration) else {
            return symbol(classicSymbol)
        }
        image.isTemplate = false
        return image
    }

    /// One thin rounded window with a small tab: lighter and simpler than the classic pair.
    private static func minimal() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let window = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 11), xRadius: 3, yRadius: 3)
            window.lineWidth = 1.2
            window.stroke()
            NSBezierPath(roundedRect: NSRect(x: 4, y: 8, width: 5.5, height: 2), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
