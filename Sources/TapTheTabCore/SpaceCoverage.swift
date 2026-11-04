import Foundation

/// How far the switcher looks beyond the desktop (Space) the user is on. A view over the
/// two stored filter keys, `currentSpaceOnly` and `showOtherSpaces`, which stay exactly as
/// they are in config files; Settings shows this as one choice so the two can no longer
/// contradict each other.
public enum SpaceCoverage: String, CaseIterable, Sendable {
    /// Only the current desktop, also inside a full-screen app (`currentSpaceOnly`).
    case currentDesktop
    /// The default. The current desktop; from a full-screen app also the windows seen
    /// earlier on other desktops and the apps whose windows can't be listed
    /// (`FullscreenEscape`, `SeenWindowRetention`). Public interfaces only.
    case automatic
    /// Every desktop and full-screen app, listed by the window server (`showOtherSpaces`,
    /// private interfaces).
    case allDesktops

    /// The coverage the filters give at run time. Older configs may have both keys on:
    /// the strict setting has always won there, so it still does.
    public init(_ options: FilterOptions) {
        if options.currentSpaceOnly {
            self = .currentDesktop
        } else if options.showOtherSpaces {
            self = .allDesktops
        } else {
            self = .automatic
        }
    }

    /// `options` with both keys set for this coverage; every other filter is untouched.
    public func applied(to options: FilterOptions) -> FilterOptions {
        var result = options
        result.currentSpaceOnly = self == .currentDesktop
        result.showOtherSpaces = self == .allDesktops
        return result
    }

    /// Whether the window server's per-Space lists are asked (the other-Spaces pass).
    public static func listsOtherSpaces(_ options: FilterOptions) -> Bool {
        SpaceCoverage(options) == .allDesktops
    }

    /// Strict coverage must not replace a windowless app entry with an off-Space window
    /// that its filter will immediately remove. All-desktops coverage may use retention
    /// as a fallback when the private listing is unavailable.
    public static func retainsSeenWindows(_ options: FilterOptions) -> Bool {
        SpaceCoverage(options) != .currentDesktop
    }
}

/// Getting out of a full-screen app. macOS gives each full-screen window a Space of its
/// own, and the Accessibility API lists only the current Space's windows for most apps,
/// so from a full-screen video every other app looked windowless and the default filter
/// hid it: the switcher showed the video alone.
public enum FullscreenEscape {
    /// A full-screen window is shown on some display right now.
    public static func isFullscreenShown(_ items: [SwitcherItem]) -> Bool {
        items.contains(where: isShownFullscreen)
    }

    /// The user is in a full-screen app: a shown full-screen window belongs to the active
    /// app or is on the switcher's display. With neither known, any shown one counts.
    public static func isActive(_ items: [SwitcherItem], context: FilterContext) -> Bool {
        items.contains { item in
            guard isShownFullscreen(item) else { return false }
            if context.activePID == nil && context.activeDisplayID == nil { return true }
            if let pid = context.activePID, item.pid == pid { return true }
            if let display = context.activeDisplayID, item.displayID == display { return true }
            return false
        }
    }

    /// Whether apps without listed windows are shown although "Show apps without windows"
    /// is off: only with the default coverage (never with the strict current-desktop
    /// setting, and not when every desktop is listed anyway) and only from a full-screen
    /// app, where such an app most likely has its windows on another desktop. Choosing
    /// one activates the app, which shows its windows' desktop.
    public static func showsAppsWithoutListedWindows(_ items: [SwitcherItem], options: FilterOptions, context: FilterContext) -> Bool {
        SpaceCoverage(options) == .automatic && isActive(items, context: context)
    }

    private static func isShownFullscreen(_ item: SwitcherItem) -> Bool {
        item.isFullscreen && item.isOnActiveSpace && !item.isMinimized && !item.isAppHidden && !item.isWindowless
    }
}

/// Which windows the Accessibility API listed before but no longer does are kept while a
/// full-screen app is shown. They are still there, on another desktop: the user just
/// entered the full-screen Space, or they were kept by an earlier refresh. Uses only
/// what the public window list says (the window still exists and is not on screen).
public enum SeenWindowRetention {
    public struct Outcome: Equatable, Sendable {
        /// Windows to keep listing, marked as not on the active Space, in input order.
        public var kept: [SwitcherItem]
        /// Windows that left the screen alive but are not kept. Held for one more refresh
        /// in case the full-screen state is reported late; never carried further.
        public var vanished: [SwitcherItem]

        public init(kept: [SwitcherItem] = [], vanished: [SwitcherItem] = []) {
            self.kept = kept
            self.vanished = vanished
        }
    }

    /// A full-screen window is on screen now that wasn't on screen and full screen before:
    /// the active Space just changed to a full-screen one.
    public static func enteredFullscreen(now: [SwitcherItem], previous: [SwitcherItem]) -> Bool {
        var before = Set<ItemID>()
        for item in previous where item.isFullscreen && item.isOnActiveSpace && !item.isMinimized {
            before.insert(item.id)
        }
        return now.contains { $0.isFullscreen && $0.isOnActiveSpace && !$0.isMinimized && !$0.isWindowless && !before.contains($0.id) }
    }

    /// Decides what stays.
    ///
    /// - Parameters:
    ///   - previous: the last snapshot's items.
    ///   - heldBack: `Outcome.vanished` of the last refresh.
    ///   - current: what this refresh found (Accessibility, reused, other-Spaces pass).
    ///   - answeredPIDs: apps asked this time that answered. Only their
    ///     windows can be missing for a reason; everyone else's were reused or kept as is.
    ///   - ignoredIDs: windows the Accessibility API listed but that are not switchable.
    ///   - onScreenIDs: windows on screen now (the current Spaces).
    ///   - windowServerOwners: owner pid of each window the window server still has.
    ///
    /// A window is a candidate when its app answered without it, it is not on screen, not
    /// minimized, and the window server still has it for the same app. Nothing is kept
    /// unless a full-screen window is shown now. Then a candidate is kept when it was
    /// already off the active Space (kept before) or the Space just changed to a
    /// full-screen one. A window that just left the screen otherwise was closed or
    /// ordered out (or went to another desktop, which only the window server can tell);
    /// keeping it would list a window the user closed.
    public static func decide(
        previous: [SwitcherItem],
        heldBack: [SwitcherItem] = [],
        current: [SwitcherItem],
        answeredPIDs: Set<Int32>,
        ignoredIDs: Set<UInt32>,
        onScreenIDs: Set<UInt32>,
        windowServerOwners: [UInt32: Int32]
    ) -> Outcome {
        var listed = Set<ItemID>()
        for item in current { listed.insert(item.id) }
        let active = FullscreenEscape.isFullscreenShown(current)
        let entered = active && enteredFullscreen(now: current, previous: previous + heldBack)

        func isCandidate(_ item: SwitcherItem) -> Bool {
            guard case .window(let number) = item.id, number != 0,
                  answeredPIDs.contains(item.pid),
                  !item.isMinimized,
                  !listed.contains(item.id),
                  !ignoredIDs.contains(number),
                  !onScreenIDs.contains(number),
                  windowServerOwners[number] == item.pid else { return false }
            return true
        }

        var outcome = Outcome()
        var seen = Set<ItemID>()
        for item in previous where isCandidate(item) && seen.insert(item.id).inserted {
            if active && (!item.isOnActiveSpace || entered) {
                var kept = item
                kept.isOnActiveSpace = false
                outcome.kept.append(kept)
            } else {
                outcome.vanished.append(item)
            }
        }
        // Held-back windows get one more chance, only on entering full screen.
        for item in heldBack where entered && isCandidate(item) && seen.insert(item.id).inserted {
            var kept = item
            kept.isOnActiveSpace = false
            outcome.kept.append(kept)
        }
        return outcome
    }
}
