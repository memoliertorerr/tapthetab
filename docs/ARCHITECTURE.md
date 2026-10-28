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
| `GridLayout` | Columns/rows/scale for the grid on a given screen. |

## macOS layer (`Sources/TapTheTab`)

| Component | Notes |
|---|---|
| `HotkeyMonitor` | Session-level `CGEventTap`. Decides synchronously whether to swallow; re-enables itself after `tapDisabledByTimeout`. Takes over ⌘⇥/⌘\` by disabling the system symbolic hotkeys while running and restoring them on stop, quit and SIGTERM/SIGINT/SIGHUP. |
| `WindowCatalog` | `CGWindowListCopyWindowInfo` gives z-order and which windows are on the current Space; the Accessibility API gives titles, minimized/fullscreen state and the elements to act on. Apps are enumerated concurrently with a 250 ms AX timeout each, off the main thread. |
| `FocusTracker` | `NSWorkspace` activation notifications plus an `AXObserver` on the frontmost app for focused-window changes feed the `RecencyTracker`. |
| `WindowActions` | Raise via `kAXRaiseAction` + `kAXMainAttribute` + app `kAXFrontmostAttribute` + activation; windowless apps are reopened through Launch Services so they create a window. |
| `ThumbnailService` | ScreenCaptureKit single-window screenshots (macOS 14+), cached per window, only when previews are enabled and Screen Recording is granted. |
| `UI/` | Non-activating `NSPanel` (never takes focus — keys come from the tap) hosting SwiftUI; Settings and Onboarding windows. |

## Permissions

- **Accessibility** — required for the event tap and AX. Without it the app shows
  onboarding and polls once a second until granted.
- **Screen Recording** — only for previews; previews are off by default.

## Private API use

| Symbol | Why | Failure mode |
|---|---|---|
| `_AXUIElementGetWindow` | Map an AX window to its window-server ID (needed to join AX data with z-order and to capture previews). | Window is skipped. |
| `CGSSetSymbolicHotKeyEnabled` | ⌘⇥ is consumed by the Window Server before event taps; the system shortcut must be switched off to use it as a trigger. | ⌘⇥ keeps opening the system switcher. |
