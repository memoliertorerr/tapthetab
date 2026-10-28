# Architecture

TapTheTab is split into a portable **core** that holds all decisions and a thin **macOS
layer** that talks to the operating system. The split is what lets the switcher's
behaviour be unit-tested on any machine, including Linux CI.

## Flow of one switch

```
 key down (⌥⇥)                                    key up (⌥)
      │                                                ▲
      ▼                                                │
 HotkeyMonitor (CGEventTap, main run loop)             │ flagsChanged
   • matches a Trigger, swallows the key               │
   • from now on swallows every key until the session ends
      │ didTrigger / keyDown / modifiersChanged (DispatchQueue.main.async)
      ▼
 SwitcherCoordinator (@MainActor)
   • items = ItemFilter.apply(FocusTracker.ordered(WindowCatalog.latest))
   • session = SwitcherSession(items, columns: panel.columns(...))
   • starts show-delay timer; refreshes the catalog in the background
   • KeyRouter: KeyPress → SwitcherInput → session.handle(...) → SwitcherEffect
      │
      ├─ .refresh            → SwitcherPanelController.update(session)
      ├─ .perform(action, i) → WindowActions.perform, optimistic item update, re-enumerate
      ├─ .activate(item)     → close panel, WindowActions.activate, FocusTracker.touch
      └─ .dismiss            → close panel
```

A tap that is released before the show delay (90 ms default) activates the pre-selected
previous window without the panel ever appearing.

## Core (`Sources/TapTheTabCore`)

| Type | Role |
|---|---|
| `SwitcherItem`, `ItemID` | Plain snapshot of a window or a windowless app. |
| `SwitcherSession` | Value-type state machine: items, query, visible ranked items, selection, locked state. `handle(_:)` returns an effect for the platform layer. |
| `FuzzyMatcher` | Token-based fuzzy scoring over title + app name with match indices for highlighting. |
| `RecencyTracker` | MRU order from focus stamps; unknown items keep platform (z-) order. |
| `ItemFilter` | Applies `FilterOptions` and `SwitcherScope` without reordering. |
| `KeyRouter` | Maps `KeyPress` to `SwitcherInput` (cycling, arrows, search text, ⇧-letter actions). |
| `Shortcut`, `KeyCode`, `ModifierFlags` | Human-readable shortcuts (`"option+tab"`) ↔ key codes. |
| `Configuration`, `ConfigStore` | Lenient JSON config with validation; atomic 0600 saves; broken files are set aside, never overwritten. |
| `GridLayout` | Columns/rows/scale for the grid on a given screen (shrinks to fit height and width). |
| `PanelLayout` | Every switcher panel size: grid and list (at most 10 rows), search bar, large-preview box, minimum and empty sizes, app headings. The UI's `SwitcherLayout` only converts it to CoreGraphics types. |
| `ItemOrdering` | Optional grouping by app (`appearance.groupByApp`): apps by their most recent window, applied after `ItemFilter` and before the session; where the grouped list puts app headings. |
| `SearchMemory` | In-memory record of which window/app was picked for which search; adds a bounded boost to matching items. |
| `AutomationCommand` | Strict parser for `tapthetab://` links (untrusted input). |
| `ShortcutConflicts` | Known system shortcuts and ⇧-reverse clashes between triggers. |
| `SpaceLayout`, `OtherSpaceWindows` | Pure logic for the opt-in other-Spaces pass: reading the Space layout and choosing which window-server windows are switchable. |
| `DiagnosticsReport` | Bug-report text: versions, permissions, counts, settings — no titles or bundle IDs. |

## macOS layer (`Sources/TapTheTab`)

| Component | Notes |
|---|---|
| `HotkeyMonitor` | Session-level `CGEventTap`. Decides synchronously whether to swallow; re-enables itself after `tapDisabledByTimeout`. Takes over ⌘⇥/⌘\` by disabling the system symbolic hotkeys while running and restoring them on stop, quit and SIGTERM/SIGINT/SIGHUP. |
| `WindowCatalog` | `CGWindowListCopyWindowInfo` gives z-order and which windows are on the current Space; the Accessibility API gives titles, minimized/fullscreen state and the elements to act on. Apps are enumerated concurrently with a 250 ms AX timeout each, off the main thread. |
| `WindowWatcher` | One `AXObserver` per regular app (window created/destroyed/retitled/minimized, app hidden/shown) whose coalesced events refresh the catalog, so the list is current when the switcher opens. |
| `FocusTracker` | `NSWorkspace` activation notifications plus an `AXObserver` on the frontmost app for focused-window changes feed the `RecencyTracker`. |
| `WindowActions` | Raise via `kAXRaiseAction` + `kAXMainAttribute` + app `kAXFrontmostAttribute` + activation; windowless apps are reopened through Launch Services so they create a window. |
| `ThumbnailService` | ScreenCaptureKit single-window screenshots (macOS 14+), cached per window, only when previews are enabled and Screen Recording is granted. |
| `UI/` | Non-activating `NSPanel` (never takes focus — keys come from the tap) hosting SwiftUI; Settings and Onboarding windows. |

## Localization

User-facing strings go through `L10n.tr("English sentence")` (App/Localization.swift),
which looks them up in `Resources/Localization/<lang>.lproj/Localizable.strings` copied
into the app bundle by `scripts/build-app.sh`. English sentences are the keys, so a
missing table still shows English. Window titles, app names and search text are never
localized. `scripts/check-strings.py` (run in CI) checks syntax, matching keys and
placeholders across languages, unused keys, and bare literals passed to SwiftUI views.

## Automation

`tapthetab://switch[?scope=…&query=…]` and `tapthetab://settings` arrive through
`NSApplicationDelegate.application(_:open:)`, are parsed by `AutomationCommand`, and can
only open TapTheTab's own UI.

## Screenshots

`TapTheTab --render-screenshots <dir>` (`make screenshots`, and every macOS CI run, which
uploads the result as the `screenshots-<sha>` artifact) is a hidden mode handled in
`TapTheTabMain` before anything else starts: no event tap, menu bar item, config file or
permission prompt. `App/ScreenshotRenderer.swift` feeds the real `SwitcherRootView` and
`SettingsView` with made-up windows (fictional titles, icons of apps that ship with macOS,
synthetic previews drawn with Core Graphics), lays the panel out with the same
`SwitcherLayout` math for a 1512×945 pt screen, and writes 2× PNGs in light and dark onto a
gradient "desktop". The switcher is drawn with `ImageRenderer`; Settings (AppKit-backed
controls) from an offscreen window that is never shown. The README images in
`docs/images/` come from that artifact.

## Permissions

- **Accessibility** — required for the event tap and AX. Without it the app shows
  onboarding and polls once a second until granted.
- **Screen Recording** — only for previews; previews are off by default.

## Private API use

All private symbols are resolved at runtime in `System/PrivateAPI.swift` with `dlsym`, so a
symbol missing from a future macOS disables one feature instead of preventing launch.

| Symbol | Why | Failure mode |
|---|---|---|
| `_AXUIElementGetWindow` | Map an AX window to its window-server ID (needed to join AX data with z-order and to capture previews). | Window is skipped. |
| `CGSSetSymbolicHotKeyEnabled` | ⌘⇥ is consumed by the Window Server before event taps; the system shortcut must be switched off to use it as a trigger. | ⌘⇥ keeps opening the system switcher. |
| `CGSMainConnectionID` | The process's window-server connection, which the two Space calls below take. | Other Spaces' windows are not listed. |
| `CGSCopyManagedDisplaySpaces` | Every Space per display, including fullscreen Spaces, and which one is shown (only with "Show windows on other Spaces"). | Other Spaces' windows are not listed. |
| `CGSCopyWindowsWithOptionsAndTags` | The windows of each Space; the Accessibility API only reports the current Space's windows for most apps. | Other Spaces' windows are not listed. |
| `GetProcessForPID` | Public but deprecated; looked up at runtime so the build stays warning-free. Gives the process serial number the two calls below take. | Windows on other Spaces are focused through the public path (the app is activated, its Space may not switch). |
| `_SLPSSetFrontProcessWithOptions` | Makes the app frontmost with the chosen window, switching to that window's Space (only with "Show windows on other Spaces"). | Same as above. |
| `SLPSPostEventRecordTo` | Makes the chosen window key (a 0x100-byte event record, posted twice). | Same as above. |
