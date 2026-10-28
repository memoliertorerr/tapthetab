import Foundation

/// One shortcut that opens the switcher, and what it shows.
public struct Trigger: Codable, Equatable, Hashable, Sendable {
    public var shortcut: Shortcut
    public var scope: SwitcherScope

    public init(shortcut: Shortcut, scope: SwitcherScope) {
        self.shortcut = shortcut
        self.scope = scope
    }
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
    public var showAppName: Bool = true
    public var theme: Theme = .system
    public var placement: DisplayPlacement = .mouse
    /// Delay before the panel appears. A quick tap within this time switches without
    /// flashing the panel. Clamped to 0...1000.
    public var showDelayMilliseconds: Int = 90

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        style = c.lenient(LayoutStyle.self, .style) ?? d.style
        size = c.lenient(ItemSize.self, .size) ?? d.size
        showPreviews = c.lenient(Bool.self, .showPreviews) ?? d.showPreviews
        showAppName = c.lenient(Bool.self, .showAppName) ?? d.showAppName
        theme = c.lenient(Theme.self, .theme) ?? d.theme
        placement = c.lenient(DisplayPlacement.self, .placement) ?? d.placement
        showDelayMilliseconds = c.lenient(Int.self, .showDelayMilliseconds) ?? d.showDelayMilliseconds
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

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Behavior()
        releaseToSwitch = c.lenient(Bool.self, .releaseToSwitch) ?? d.releaseToSwitch
        searchEnabled = c.lenient(Bool.self, .searchEnabled) ?? d.searchEnabled
        startOnPrevious = c.lenient(Bool.self, .startOnPrevious) ?? d.startOnPrevious
        mouseHoverSelects = c.lenient(Bool.self, .mouseHoverSelects) ?? d.mouseHoverSelects
        wrapAround = c.lenient(Bool.self, .wrapAround) ?? d.wrapAround
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
            if trigger.shortcut.modifiers.subtracting(.shift).isEmpty {
                notes.append("Shortcut \(trigger.shortcut.displayString) needs ⌘, ⌥, ⌃ or fn; it was ignored.")
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

        let cleaned = copy.filters.excludedBundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var uniq = Set<String>()
        copy.filters.excludedBundleIDs = cleaned.filter { uniq.insert($0.lowercased()).inserted }

        return (copy, notes)
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
