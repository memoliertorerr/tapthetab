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
| `PanelLayout` | Every switcher panel size: grid and list (at most 10 rows), search bar, the large preview's box and the card it floats on (scaled by `largePreviewPercent` (25–150 %, screen-limited), hugging the window's proportions), minimum and empty sizes, app headings. The UI's `SwitcherLayout` only converts it to CoreGraphics types. |
| `PanelPlacement` | Where the main block and the preview card go on a screen (default, remembered `BlockPosition`s, clamped inside the visible frame). |
| `ColorMath`, `ColorTheme`, `GrainTexture` | Arc-style themes (ported from Little Joan): presets, colors muted into a light or dark band in OKLCH, the gradient's stops and blobs, deterministic grain pixels. |
| `QuickSelect`, `DisplayMove` | Which modifier + digit picks a window and its badge; moving a window frame to the next display. |
| `ItemOrdering` | Optional grouping by app (`appearance.groupByApp`): apps by their most recent window, applied after `ItemFilter` and before the session; where the grouped list puts app headings; the switcher's display first (`displayFirst`, before grouping so groups stay whole); pinned apps' windows first (`pinnedFirst`). |
| `AppVersion`, `ReleaseFeed`, `Checksums`, `UpdatePolicy` | Update checks: SemVer ordering, parsing GitHub's latest-release response (size-capped, asset URLs only from GitHub hosts), `SHA256SUMS.txt`, whether a check is due (once a day, only when enabled). |
| `WineNames` | Readable app names for Wine/CrossOver windows: the `.exe` name from the loader's arguments. |
| `LargePreviewCaptureSchedule`, `PreviewCaptureTarget`, `PreviewImageRetention`, `PreviewSelectionAnimation` | Capture immediately after a pause and settle during rapid cycling; retain a few recent sharp previews; snap rapid selection changes instead of stacking animations. |
| `SearchMemory` | In-memory record of which window/app was picked for which search; adds a bounded boost to matching items. |
| `AutomationCommand` | Strict parser for `tapthetab://` links (untrusted input). |
| `ShortcutConflicts` | Known system shortcuts and ⇧-reverse clashes between triggers. |
| `SpaceLayout`, `OtherSpaceWindows` | Pure logic for the opt-in other-Spaces pass: reading the Space layout and choosing which window-server windows are switchable. |
| `WindowAdmission` | Which Accessibility windows are switchable (standard; titled dialogs; titled, normal-layer, sizable "unknown" windows such as Wine's). |
| `DiagnosticsReport` | Bug-report text: versions, permissions, counts, settings — no titles or bundle IDs. |

## macOS layer (`Sources/TapTheTab`)

| Component | Notes |
|---|---|
| `HotkeyMonitor` | Session-level `CGEventTap`. Decides synchronously whether to swallow; re-enables itself after `tapDisabledByTimeout`. Takes over ⌘⇥/⌘\` by disabling the system symbolic hotkeys while running and restoring them on stop, quit and SIGTERM/SIGINT/SIGHUP. |
| `WindowCatalog` | `CGWindowListCopyWindowInfo` gives z-order and which windows are on the current Space; the Accessibility API gives titles, minimized/fullscreen state and the elements to act on. Apps are enumerated concurrently with a 250 ms AX timeout each, off the main thread. |
| `WindowWatcher` | One `AXObserver` per regular app (window created/destroyed/retitled/minimized, app hidden/shown) whose coalesced events refresh the catalog, so the list is current when the switcher opens. |
| `FocusTracker` | `NSWorkspace` activation notifications plus an `AXObserver` on the frontmost app for focused-window changes feed the `RecencyTracker`. |
| `WindowActions` | Raise via `kAXRaiseAction` + `kAXMainAttribute`, then the window server makes the app frontmost with only that window (`_SLPSSetFrontProcessWithOptions` + a make-key event record), like a click on it; the app's other windows stay put. If those functions are missing: app `kAXFrontmostAttribute` + activation, which may bring all its windows forward. Windowless apps are reopened through Launch Services so they create a window. |
| `ThumbnailService` | ScreenCaptureKit single-window screenshots (macOS 14+), cached per window, only when previews are enabled and Screen Recording is granted. Captures use the window’s pixel scale, run four at a time with priority for large previews/peek, and share in-flight window-list fetches. |
| `Updater`, `UpdateInstaller` | The only network access (see Network below). `Updater` (main actor) schedules checks and holds the state Settings and the Software Update window show; `UpdateInstaller` downloads, verifies and hands over to a small replace script. |
| `UI/` | Two non-activating, transparent `NSPanel`s (never take focus — keys come from the tap) hosting SwiftUI: the main block and the large preview's card, each draggable while the switcher is open. Each draws its own backdrop (`PanelBackdrop.swift`): the system's Liquid Glass on macOS 26 (`glassEffect`, Clear or Tinted), a blur with a glass-like rim before, or the classic HUD material, with an optional theme gradient and grain on top. Settings and Onboarding windows. |

## Preview responsiveness

Image updates use transactions without animation: a sharp capture replaces the small
thumbnail immediately. The preview card alone observes the sharp-image store, so a late
result for another window does not redraw the grid or list. Card geometry ignores tiny capture-rounding
differences, but follows the sharp image when a resized window no longer matches its
cached thumbnail.

Normal selection steps keep the slide/reshape animation. Rapid steps snap to the latest
selection; Reduce Motion always disables animation. Thumbnail deliveries are batched for
about one frame, and animated shadow work is deferred until the selection settles.
Sharp captures run immediately after a pause, settle for 80 ms while cycling, and are
scheduled one at a time with session-token guards. Up to three recent images are
retained with a 16-megapixel soft budget (the selected and newest image are protected). Nothing is saved to disk. A larger preview box
requests another capture even when the selected window did not change.

## Panel dragging and Settings actions

While the switcher is visible, a local AppKit mouse monitor tracks a left-button drag
starting in either panel, independently of SwiftUI row/card gestures and shortcut
modifiers. Movement begins after four points; ordinary clicks and scroll-wheel events
still reach the content. During a drag, hover selection is suppressed; the ending click
does not switch windows. Existing `PanelPlacement` clamping and fractional saved positions
remain unchanged. Saving positions updates only the coordinator’s stored positions,
without closing the active switching session. Hiding mid-drag also saves movement.
The monitor is removed when the switcher closes.

Settings → About can reopen the shared tour window with the current shortcut and theme.
Its Quit TapTheTab button calls normal application termination, so the coordinator stops
the event tap and restores system shortcuts.

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

`--render-demo <file.png>` (`make demo`) draws the demo animation the same way: 13 frames
of the grid, a search narrowing the list, and a themed list, encoded as an animated PNG
with ImageIO (≤ 3 MB). CI then runs `scripts/check-screenshots.py`, which compares each
rendered PNG with `docs/images/screenshot-reference.json` (size and a 256-bit perceptual
hash) and fails on a visible change; `--update` accepts the new images.

## Website

`site/` is a static page (no JavaScript, no external fonts or analytics, strict CSP).
`scripts/build-site.sh` (`make site`) copies it with the images from `docs/images/` into
`dist/site`; `.github/workflows/pages.yml` publishes it to GitHub Pages on pushes to
`main` that touch it.

## Network

TapTheTab goes online only to ask GitHub for the latest release: once a day when
`behavior.checkForUpdates` is on (off by default), or when the user clicks Check for
Updates. Requests use an ephemeral `URLSession` (no cookies, cache or credentials) and
carry only `Accept` and `User-Agent: TapTheTab/<version>`; responses are size-capped.

Installing is always a click (Install and Relaunch):

1. The release's `.dmg` and `SHA256SUMS.txt` are downloaded into a new 0700 folder.
2. The image's SHA-256 must match before it is mounted (read-only, hidden from Finder).
3. The copied `TapTheTab.app` must pass a strict code-signature check for an Apple-issued
   Developer ID certificate with the running app's team ID and bundle ID, and its version
   must equal the release's.
4. A fixed `/bin/sh` script (paths only as arguments) waits for TapTheTab to quit, swaps
   the bundle (restoring the old one on failure), opens the new version and moves the old
   one to the Trash.

It does not self-update when it was installed by Homebrew (it shows
`brew upgrade --cask tapthetab`), when the running copy has no Developer ID (ad-hoc
builds), runs from App Translocation, or cannot write to its folder; it then opens the
release page instead.

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
| `GetProcessForPID` | Public but deprecated; looked up at runtime so the build stays warning-free. Gives the process serial number the two calls below take. | Windows are focused through the public path: the app is activated, which can bring all its windows forward, and its Space may not switch. |
| `_SLPSSetFrontProcessWithOptions` | Makes the app frontmost with only the chosen window brought forward (every switch), switching to that window's Space if needed. Public activation raises all of an app's windows. | Same as above. |
| `SLPSPostEventRecordTo` | Makes the chosen window key (a 0x100-byte event record, posted twice). | Same as above. |
