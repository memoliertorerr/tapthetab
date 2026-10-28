import Foundation

/// One Space (virtual desktop or fullscreen Space) as the window server lists it.
public struct SpaceInfo: Equatable, Sendable {
    public var id: UInt64
    /// A Space holding one fullscreen window (or a Split View pair).
    public var isFullscreen: Bool
    /// The Space currently shown on its display.
    public var isCurrent: Bool

    public init(id: UInt64, isFullscreen: Bool = false, isCurrent: Bool = false) {
        self.id = id
        self.isFullscreen = isFullscreen
        self.isCurrent = isCurrent
    }
}

public enum SpaceLayout {
    /// Space types in the window server's list. Other types (system Spaces) are skipped.
    static let userSpaceType = 0
    static let fullscreenSpaceType = 4

    /// Reads the per-display dictionaries returned by the window server's "managed display
    /// spaces" call: each has a "Spaces" array of dictionaries with an "id64" (or
    /// "ManagedSpaceID") and a "type", and a "Current Space" dictionary.
    ///
    /// Returns every user and fullscreen Space once, in display order then left to right.
    /// Anything malformed is skipped: an unexpected shape yields fewer Spaces, never a crash.
    public static func spaces(fromManagedDisplaySpaces displays: [[String: Any]]) -> [SpaceInfo] {
        var result: [SpaceInfo] = []
        var seen = Set<UInt64>()
        var current = Set<UInt64>()
        for display in displays {
            if let space = display["Current Space"] as? [String: Any], let id = spaceID(space) {
                current.insert(id)
            }
        }
        for display in displays {
            guard let spaces = display["Spaces"] as? [Any] else { continue }
            for case let space as [String: Any] in spaces {
                guard let id = spaceID(space), seen.insert(id).inserted else { continue }
                let type = space["type"].flatMap(integer) ?? Int64(userSpaceType)
                guard type == Int64(userSpaceType) || type == Int64(fullscreenSpaceType) else { continue }
                result.append(SpaceInfo(id: id, isFullscreen: type == Int64(fullscreenSpaceType), isCurrent: current.contains(id)))
            }
        }
        return result
    }

    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        guard let value = space["id64"].flatMap(integer) ?? space["ManagedSpaceID"].flatMap(integer),
              value > 0 else { return nil }
        return UInt64(value)
    }

    /// Numbers arrive as NSNumber from the window server and as Swift integers in tests.
    static func integer(_ value: Any) -> Int64? {
        if let number = value as? Int { return Int64(number) }
        if let number = value as? Int64 { return number }
        if let number = value as? Int32 { return Int64(number) }
        if let number = value as? UInt32 { return Int64(number) }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }
}

/// What the window server says about one window (from its public description).
public struct WindowServerWindow: Equatable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var layer: Int
    public var alpha: Double
    public var width: Double
    public var height: Double
    /// Needs the Screen Recording permission for other apps' windows; usually nil.
    public var name: String?

    public init(id: UInt32, pid: Int32, layer: Int = 0, alpha: Double = 1, width: Double, height: Double, name: String? = nil) {
        self.id = id
        self.pid = pid
        self.layer = layer
        self.alpha = alpha
        self.width = width
        self.height = height
        self.name = name
    }
}

/// A window found on a Space that is not currently shown.
public struct SpaceWindowCandidate: Equatable, Sendable {
    public var windowID: UInt32
    /// Index of its Space in the list given to `candidates`.
    public var spaceIndex: Int
    public var isFullscreenSpace: Bool

    public init(windowID: UInt32, spaceIndex: Int, isFullscreenSpace: Bool = false) {
        self.windowID = windowID
        self.spaceIndex = spaceIndex
        self.isFullscreenSpace = isFullscreenSpace
    }
}

/// Decides which window-server windows on other Spaces become switcher entries.
///
/// The Accessibility API only reports windows on the current Space for most apps, so the
/// window server is asked for the windows of every Space; these functions turn its answer
/// into an ordered, de-duplicated list.
public enum OtherSpaceWindows {
    /// Smaller windows are helpers (drag images, invisible anchors), not documents.
    public static let minimumSide: Double = 50

    /// Window IDs worth describing, in Space order then front to back.
    ///
    /// `windowIDsBySpace[i]` lists the windows of `spaces[i]` front to back; it may be
    /// shorter than `spaces` when the time budget ran out. A window on any current Space is
    /// left out even if it is also on another one (windows assigned to all Spaces): the
    /// Accessibility API is authoritative there. So is every ID in `excluding` (windows
    /// already found another way). Each window is returned once, for its first Space.
    public static func candidates(
        spaces: [SpaceInfo],
        windowIDsBySpace: [[UInt32]],
        excluding: Set<UInt32>
    ) -> [SpaceWindowCandidate] {
        var onCurrent = Set<UInt32>()
        for (space, ids) in zip(spaces, windowIDsBySpace) where space.isCurrent {
            onCurrent.formUnion(ids)
        }
        var seen = Set<UInt32>()
        var result: [SpaceWindowCandidate] = []
        for (index, pair) in zip(spaces, windowIDsBySpace).enumerated() where !pair.0.isCurrent {
            for id in pair.1 where id != 0 && !onCurrent.contains(id) && !excluding.contains(id) {
                guard seen.insert(id).inserted else { continue }
                result.append(SpaceWindowCandidate(windowID: id, spaceIndex: index, isFullscreenSpace: pair.0.isFullscreen))
            }
        }
        return result
    }

    /// Whether a described window looks like a normal document window: on the normal
    /// layer, not fully transparent and at least `minimumSide` points on each side.
    public static func isSwitchable(_ window: WindowServerWindow) -> Bool {
        window.layer == 0 && window.alpha > 0 && window.width >= minimumSide && window.height >= minimumSide
    }

    /// The candidates to show: described, switchable and owned by one of the apps in
    /// `appOrder` (pid → position in the app list). Ordered by app, then Space, then front
    /// to back, so they follow the current Space's windows grouped like the rest.
    public static func select(
        _ candidates: [SpaceWindowCandidate],
        descriptions: [UInt32: WindowServerWindow],
        appOrder: [Int32: Int]
    ) -> [SpaceWindowCandidate] {
        var kept: [(candidate: SpaceWindowCandidate, app: Int, position: Int)] = []
        for (position, candidate) in candidates.enumerated() {
            guard let window = descriptions[candidate.windowID], isSwitchable(window),
                  let app = appOrder[window.pid] else { continue }
            kept.append((candidate, app, position))
        }
        kept.sort { a, b in
            if a.app != b.app { return a.app < b.app }
            if a.candidate.spaceIndex != b.candidate.spaceIndex { return a.candidate.spaceIndex < b.candidate.spaceIndex }
            return a.position < b.position
        }
        return kept.map(\.candidate)
    }

    /// Title for a window on another Space: the first non-empty one of the Accessibility
    /// title (when an element is known), the title last seen, and the window server's name
    /// (Screen Recording only). Empty means "show the app name".
    public static func title(accessibility: String?, previous: String?, windowServer: String?) -> String {
        for candidate in [accessibility, previous, windowServer] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return candidate }
        }
        return ""
    }
}
