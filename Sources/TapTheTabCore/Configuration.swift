import Foundation

/// One shortcut that opens the switcher, and what it shows.
public struct Trigger: Codable, Equatable, Hashable, Sendable {
    public var shortcut: Shortcut
    public var scope: SwitcherScope
    /// The layout this shortcut opens; nil uses `Appearance.style`.
    public var style: LayoutStyle?

    public init(shortcut: Shortcut, scope: SwitcherScope, style: LayoutStyle? = nil) {
        self.shortcut = shortcut
        self.scope = scope
        self.style = style
    }

    private enum CodingKeys: String, CodingKey {
        case shortcut, scope, style
    }

    /// `shortcut` and `scope` are required (a trigger without them is dropped); a missing
    /// or unknown `style` is nil, so it never costs the trigger.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortcut = try c.decode(Shortcut.self, forKey: .shortcut)
        scope = try c.decode(SwitcherScope.self, forKey: .scope)
        style = c.lenient(LayoutStyle.self, .style)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shortcut, forKey: .shortcut)
        try c.encode(scope, forKey: .scope)
        try c.encodeIfPresent(style, forKey: .style)
    }
}

/// How the menu bar icon is drawn.
public enum MenuBarIconStyle: String, Codable, Sendable, CaseIterable {
    /// The original outline icon.
    case classic
    /// A solid version of the icon.
    case filled
    /// A reduced, lighter glyph.
    case minimal
    /// Tinted with the current colour theme.
    case themed
}

public enum LayoutStyle: String, Codable, Sendable, CaseIterable {
    /// Cards in a grid, like ⌘⇥ but per window.
    case grid
    /// A vertical list with a search field, like a launcher.
    case list
}

public enum ItemSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    /// Card size in points for the grid style.
    public var cardSize: Size {
        switch self {
        case .small: return Size(width: 120, height: 110)
        case .medium: return Size(width: 168, height: 150)
        case .large: return Size(width: 232, height: 200)
        }
    }
}

public enum Theme: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

/// The two Liquid Glass variations macOS and iOS offer in their Appearance settings.
public enum GlassStyle: String, Codable, Sendable, CaseIterable {
    /// More see-through: the desktop shows through the panel.
    case clear
    /// Frosted and more opaque, for higher contrast.
    case tinted
}

/// Which display the switcher appears on.
public enum DisplayPlacement: String, Codable, Sendable, CaseIterable {
    /// The display with the mouse pointer.
    case mouse
    /// The display holding the frontmost window.
    case activeWindow
    /// The main display (menu bar).
    case main
}

public struct Appearance: Codable, Equatable, Sendable {
    public var style: LayoutStyle = .grid
    public var size: ItemSize = .medium
    /// Live window previews. Needs the Screen Recording permission on macOS.
    public var showPreviews: Bool = false
    /// With previews on: cards and list rows show a live thumbnail of their window (with
    /// the app icon as a badge) instead of the app icon alone.
    public var windowThumbnails: Bool = true
    /// With previews on: the larger preview of the selected window on its own card.
    public var showLargePreview: Bool = true
    /// Size of the large preview of the selected window, in percent of the full-size
    /// box (previews mode). Clamped to 25...100.
    public var largePreviewPercent: Int = Appearance.defaultLargePreviewPercent
    /// Where the user dragged the main block (search plus grid or list); nil: centred.
    public var panelPosition: BlockPosition?
    /// Where the user dragged the large preview's card; nil: just above the main block.
    public var previewPosition: BlockPosition?
    public var showAppName: Bool = true
    /// Keep each app's windows together: apps in the order of their most recent window,
    /// each app's windows in recency order. The list style adds an app-name heading per
    /// app while not searching. Search results are always ranked by match.
    public var groupByApp: Bool = false
    /// The menu bar icon. When hidden, opening TapTheTab again (or tapthetab://settings)
    /// shows Settings.
    public var showMenuBarIcon: Bool = true
    public var menuBarIconStyle: MenuBarIconStyle = .classic
    public var theme: Theme = .system
    /// Draw the switcher panel and the preview card in Liquid Glass (macOS 26 and later;
    /// earlier versions get a translucent look close to it). Off: the classic dark panel.
    public var liquidGlass: Bool = true
    /// Which Liquid Glass variation to use when `liquidGlass` is on.
    public var glassStyle: GlassStyle = .clear
    /// A soft gradient with grain over the panel's glass or blur (Arc-style themes);
    /// `ColorTheme.none` for the backdrop alone.
    public var colorTheme: ColorTheme = .none
    public var placement: DisplayPlacement = .mouse
    /// Delay before the panel appears. A quick tap within this time switches without
    /// flashing the panel. Clamped to 0...1000.
    public var showDelayMilliseconds: Int = 90
    /// Animate the panel and its selection. Off: changes appear at once (the app also
    /// skips animations when the system's Reduce Motion is on).
    public var animations: Bool = true

    public static let defaultLargePreviewPercent = 66
    public static let largePreviewPercentRange: ClosedRange<Int> = 25...100

    /// `largePreviewPercent` as a fraction for `PanelLayout` (clamped, so a value that
    /// slipped past validation still lays out sensibly).
    public var largePreviewScale: Double {
        let range = Appearance.largePreviewPercentRange
        return Double(min(max(largePreviewPercent, range.lowerBound), range.upperBound)) / 100
    }

    public init() {}

    /// This appearance as `trigger` shows it: its own `style` when it has one.
    public func effective(for trigger: Trigger) -> Appearance {
        guard let style = trigger.style else { return self }
        var copy = self
        copy.style = style
        return copy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        style = c.lenient(LayoutStyle.self, .style) ?? d.style
        size = c.lenient(ItemSize.self, .size) ?? d.size
        showPreviews = c.lenient(Bool.self, .showPreviews) ?? d.showPreviews
        windowThumbnails = c.lenient(Bool.self, .windowThumbnails) ?? d.windowThumbnails
        showLargePreview = c.lenient(Bool.self, .showLargePreview) ?? d.showLargePreview
        largePreviewPercent = c.lenient(Int.self, .largePreviewPercent) ?? d.largePreviewPercent
        panelPosition = c.lenient(BlockPosition.self, .panelPosition)
        previewPosition = c.lenient(BlockPosition.self, .previewPosition)
        showAppName = c.lenient(Bool.self, .showAppName) ?? d.showAppName
        groupByApp = c.lenient(Bool.self, .groupByApp) ?? d.groupByApp
        showMenuBarIcon = c.lenient(Bool.self, .showMenuBarIcon) ?? d.showMenuBarIcon
        menuBarIconStyle = c.lenient(MenuBarIconStyle.self, .menuBarIconStyle) ?? d.menuBarIconStyle
        theme = c.lenient(Theme.self, .theme) ?? d.theme
        liquidGlass = c.lenient(Bool.self, .liquidGlass) ?? d.liquidGlass
        glassStyle = c.lenient(GlassStyle.self, .glassStyle) ?? d.glassStyle
        colorTheme = c.lenient(ColorTheme.self, .colorTheme) ?? d.colorTheme
        placement = c.lenient(DisplayPlacement.self, .placement) ?? d.placement
        showDelayMilliseconds = c.lenient(Int.self, .showDelayMilliseconds) ?? d.showDelayMilliseconds
        animations = c.lenient(Bool.self, .animations) ?? d.animations
    }
}

public struct Behavior: Codable, Equatable, Sendable {
    /// Releasing the trigger modifiers activates the selection (⌘⇥ style).
    public var releaseToSwitch: Bool = true
    /// Typing while the switcher is open filters the list.
    public var searchEnabled: Bool = true
    /// Open with the second entry selected, so a tap goes to the previous window.
    public var startOnPrevious: Bool = true
    public var mouseHoverSelects: Bool = true
    public var wrapAround: Bool = true
    /// ⌘1…⌘9 (another modifier when the trigger uses ⌘, see `QuickSelect`) switch to the
    /// first nine items at once.
    public var quickSelect: Bool = true
    /// Look for a newer release on GitHub once a day. Off by default: it is the app's
    /// only network access, and the user turns it on. Checking by hand works either way.
    public var checkForUpdates: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Behavior()
        releaseToSwitch = c.lenient(Bool.self, .releaseToSwitch) ?? d.releaseToSwitch
        searchEnabled = c.lenient(Bool.self, .searchEnabled) ?? d.searchEnabled
        startOnPrevious = c.lenient(Bool.self, .startOnPrevious) ?? d.startOnPrevious
        mouseHoverSelects = c.lenient(Bool.self, .mouseHoverSelects) ?? d.mouseHoverSelects
        wrapAround = c.lenient(Bool.self, .wrapAround) ?? d.wrapAround
        quickSelect = c.lenient(Bool.self, .quickSelect) ?? d.quickSelect
        checkForUpdates = c.lenient(Bool.self, .checkForUpdates) ?? d.checkForUpdates
    }
}

/// Everything the user can configure. Saved as pretty-printed JSON; every field is
/// optional when reading, so hand-edited or older files keep working.
public struct Configuration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int = Configuration.currentVersion
    public var triggers: [Trigger] = Configuration.defaultTriggers
    public var filters: FilterOptions = FilterOptions()
    public var appearance: Appearance = Appearance()
    public var behavior: Behavior = Behavior()

    public static let defaultTriggers: [Trigger] = [
        Trigger(shortcut: .optionTab, scope: .allWindows),
        Trigger(shortcut: .optionGrave, scope: .activeApp),
    ]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Configuration()
        version = c.lenient(Int.self, .version) ?? d.version
        triggers = c.lenientArray(Trigger.self, .triggers) ?? d.triggers
        filters = c.lenient(FilterOptions.self, .filters) ?? d.filters
        appearance = c.lenient(Appearance.self, .appearance) ?? d.appearance
        behavior = c.lenient(Behavior.self, .behavior) ?? d.behavior
    }

    /// Returns a copy with impossible values fixed, plus a human-readable note per fix.
    public func validated() -> (Configuration, [String]) {
        var copy = self
        var notes: [String] = []

        if copy.version > Configuration.currentVersion {
            notes.append("Config version \(copy.version) is newer than this app understands (\(Configuration.currentVersion)); unknown settings are ignored.")
        }
        copy.version = Configuration.currentVersion

        var seen = Set<Shortcut>()
        var kept: [Trigger] = []
        for trigger in copy.triggers {
            // ⇧ reverses and fn is set by the keyboard on its own (arrows, F-keys), so
            // neither can hold a switcher open: a trigger needs ⌘, ⌥ or ⌃.
            if trigger.shortcut.modifiers.intersection([.command, .option, .control]).isEmpty {
                notes.append("Shortcut \(trigger.shortcut.displayString) needs ⌘, ⌥ or ⌃; it was ignored.")
                continue
            }
            if !seen.insert(trigger.shortcut).inserted {
                notes.append("Shortcut \(trigger.shortcut.displayString) is listed twice; the duplicate was ignored.")
                continue
            }
            kept.append(trigger)
        }
        if kept.isEmpty {
            notes.append("No usable shortcut configured; using the defaults.")
            kept = Configuration.defaultTriggers
        }
        copy.triggers = kept

        let delay = copy.appearance.showDelayMilliseconds
        if !(0...1000).contains(delay) {
            copy.appearance.showDelayMilliseconds = min(max(delay, 0), 1000)
            notes.append("showDelayMilliseconds must be between 0 and 1000; it was set to \(copy.appearance.showDelayMilliseconds).")
        }

        let percent = copy.appearance.largePreviewPercent
        let percentRange = Appearance.largePreviewPercentRange
        if !percentRange.contains(percent) {
            copy.appearance.largePreviewPercent = min(max(percent, percentRange.lowerBound), percentRange.upperBound)
            notes.append("largePreviewPercent must be between \(percentRange.lowerBound) and \(percentRange.upperBound); it was set to \(copy.appearance.largePreviewPercent).")
        }

        copy.appearance.colorTheme = copy.appearance.colorTheme.validated()

        // Hand-edited positions outside the screen are pulled back onto it.
        copy.appearance.panelPosition = copy.appearance.panelPosition.map(\.clamped)
        copy.appearance.previewPosition = copy.appearance.previewPosition.map(\.clamped)

        copy.filters.excludedBundleIDs = Self.cleanedBundleIDs(copy.filters.excludedBundleIDs)
        copy.filters.pinnedBundleIDs = Self.cleanedBundleIDs(copy.filters.pinnedBundleIDs)

        return (copy, notes)
    }

    /// Trimmed, without empty entries, without case-insensitive duplicates (first kept).
    static func cleanedBundleIDs(_ ids: [String]) -> [String] {
        var uniq = Set<String>()
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && uniq.insert($0.lowercased()).inserted }
    }

    /// The trigger whose shortcut exactly matches, if any.
    public func trigger(matching shortcut: Shortcut) -> Trigger? {
        triggers.first { $0.shortcut == shortcut }
    }
}

/// Decodes an array element by element, dropping elements that fail.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or nil when it is missing or has the wrong type/value.
    /// Lets one bad setting fall back to its default instead of rejecting the whole file.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Like `lenient`, but keeps the valid elements of an array with some invalid ones.
    func lenientArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        guard let items = (try? decodeIfPresent([Lossy<T>].self, forKey: key)) ?? nil else { return nil }
        return items.compactMap(\.value)
    }
}
