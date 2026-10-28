<div align="center">

# TapTheTab

**Every window, one tap away.** A fast, keyboard-first window switcher for macOS.

Hold <kbd>⌥</kbd>, tap <kbd>⇥</kbd>, see every window. Type to search. Let go to switch.

[![CI](https://github.com/memoliertorerr/tapthetab/actions/workflows/ci.yml/badge.svg)](https://github.com/memoliertorerr/tapthetab/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/memoliertorerr/tapthetab?include_prereleases&sort=semver)](https://github.com/memoliertorerr/tapthetab/releases)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

macOS's <kbd>⌘</kbd><kbd>⇥</kbd> switches **apps**, not windows. If you have three Safari
windows and two VS Code projects open, getting to the right one means ⌘⇥, then ⌘\`, then
guessing. TapTheTab shows **every window** in one place, ordered by when you last used it,
and lets you jump to any of them by typing a few letters of its title.

It is a from-scratch take on the idea popularised by [AltTab](https://github.com/lwouis/alt-tab-macos),
built around three goals:

1. **Search first.** Typing while the switcher is open fuzzy-matches window titles *and*
   app names. `⌥⇥ sl ⌥` → Slack. `⌥⇥ gh pull` → the GitHub pull-request tab in whichever
   browser it lives in.
2. **Privacy by default.** No network access, no telemetry, no analytics, ever. Window
   previews are opt-in, so out of the box TapTheTab needs only the Accessibility
   permission, not Screen Recording.
3. **Small and hackable.** A plain-text JSON config, a pure-Swift core with unit tests that
   run on any platform, and a thin macOS layer on top.

## Features

- **All windows, most recent first** — including minimized windows and hidden apps
  (each can be filtered out).
- **Type to search** — fuzzy, case- and accent-insensitive, matches titles and app names,
  highlights what matched, and remembers what you picked so it ranks first next time.
- **Same-app switcher** — <kbd>⌥</kbd><kbd>\`</kbd> cycles only the frontmost app's windows.
- **Act without switching** — close, minimize, fullscreen, hide or quit the selected
  window's app straight from the switcher.
- **Quick tap = previous window** — a tap under the show delay (90 ms by default) switches
  back without the panel ever flashing.
- **Grid or list layout**, three sizes, light/dark/system theme, shows on the display with
  your mouse (or the active window, or the main display).
- **Optional live previews** (macOS 14+, needs Screen Recording), with a large preview of
  the selected window.
- **Speaks your language** — English, Italian and Turkish, with VoiceOver support.
- **Scriptable** — `tapthetab://` links open the switcher pre-filtered from launchers,
  Shortcuts or the terminal (see [Automation](#automation)).
- **Use ⌘⇥ if you like** — TapTheTab can take over the system shortcut while it runs and
  hands it back when it quits.
- **Any shortcut you like** — record one in Settings, or edit the config.
- **Always current** — window changes are watched live, so the list is right the moment
  the switcher opens.
- **Menu bar app** with Settings, pause/resume and launch at login.
- **Hand-editable config** that is reloaded live when you save it.

## Install

**Homebrew**

```bash
brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab
brew install --cask tapthetab
```

**Manually**

1. Download `TapTheTab-<version>.dmg` (or `.zip`) from the
   [latest release](https://github.com/memoliertorerr/tapthetab/releases/latest).
2. Drag **TapTheTab** into **Applications** and open it.
3. Grant **Accessibility** when asked (System Settings → Privacy & Security →
   Accessibility). That's the only required permission.

> [!NOTE]
> Release builds are not yet notarized by Apple, so the first launch is blocked by
> Gatekeeper. Either right-click the app → **Open** → **Open**, or go to System Settings →
> Privacy & Security and click **Open Anyway**. From a terminal you can instead run
> `xattr -dr com.apple.quarantine /Applications/TapTheTab.app`.
> Each release lists SHA-256 checksums in `SHA256SUMS.txt`.

> [!TIP]
> Because builds are ad-hoc signed, macOS treats every update as a new app and may ask for
> Accessibility again. If the shortcut stops working after an update, remove TapTheTab
> from the Accessibility list and add it back.

## Using it

| Keys (while holding the trigger modifier) | What happens |
|---|---|
| <kbd>⌥</kbd><kbd>⇥</kbd> | Open the switcher, select the previous window |
| <kbd>⇥</kbd> / <kbd>⇧</kbd><kbd>⇥</kbd> | Next / previous window |
| <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Move around the grid |
| *letters, digits* | Search |
| <kbd>⌫</kbd> | Delete the last search character |
| *release* <kbd>⌥</kbd> | Switch to the selection |
| <kbd>↩</kbd> | Switch to the selection |
| <kbd>⎋</kbd> | Clear the search; press again to close |
| <kbd>Space</kbd> (empty search) | Keep the switcher open after you release <kbd>⌥</kbd> |
| <kbd>⇧</kbd><kbd>W</kbd> | Close the window |
| <kbd>⇧</kbd><kbd>M</kbd> | Minimize / restore the window |
| <kbd>⇧</kbd><kbd>F</kbd> | Toggle fullscreen |
| <kbd>⇧</kbd><kbd>H</kbd> | Hide / show the app |
| <kbd>⇧</kbd><kbd>Q</kbd> | Quit the app |
| <kbd>⌥</kbd><kbd>\`</kbd> | Same thing, but only the current app's windows |

The mouse works too: hover to select, click to switch, click outside to dismiss.

## Configuration

Everything in Settings is stored in
`~/Library/Application Support/TapTheTab/config.json` (owner-only permissions). Edit it
by hand if you prefer — TapTheTab reloads it as soon as you save. Unknown or missing keys
fall back to defaults, and a file that can't be read is set aside as
`config.invalid-<timestamp>.json` instead of being overwritten.

```json
{
  "triggers": [
    { "shortcut": "option+tab", "scope": "allWindows" },
    { "shortcut": "option+`",   "scope": "activeApp" }
  ],
  "behavior": {
    "releaseToSwitch": true,
    "searchEnabled": true,
    "startOnPrevious": true,
    "mouseHoverSelects": true,
    "wrapAround": true
  },
  "appearance": {
    "style": "grid",
    "size": "medium",
    "showPreviews": false,
    "showAppName": true,
    "theme": "system",
    "placement": "mouse",
    "showDelayMilliseconds": 90
  },
  "filters": {
    "showMinimized": true,
    "showHiddenApps": true,
    "showWindowlessApps": false,
    "currentSpaceOnly": false,
    "currentDisplayOnly": false,
    "excludedBundleIDs": ["com.apple.finder"]
  }
}
```

- **Shortcuts** are written as `modifier+…+key`, e.g. `command+tab`, `ctrl+shift+space`,
  `option+grave`. A shortcut needs at least one of ⌘ ⌥ ⌃ fn.
- **Scopes:** `allWindows`, `activeApp` (the frontmost app's windows) and `apps` (one
  entry per app, like ⌘⇥).
- **Styles:** `grid` or `list`. **Sizes:** `small`, `medium`, `large`.
  **Placement:** `mouse`, `activeWindow`, `main`.

## Automation

TapTheTab answers to `tapthetab://` links, so launchers (Raycast, Alfred), Shortcuts,
Keyboard Maestro or a terminal can open it:

| Link | Opens |
|---|---|
| `tapthetab://switch` | The switcher, locked open (no key to hold) |
| `tapthetab://switch?query=slack` | The switcher, already searching for "slack" |
| `tapthetab://switch?scope=activeApp` | Only the frontmost app's windows (`allWindows`, `activeApp`, `apps`) |
| `tapthetab://settings` | Settings |

```bash
open "tapthetab://switch?query=pull%20request"
```

Links can only open TapTheTab's own windows; they can never close, quit or move
anything.

## Permissions and privacy

| Permission | Why | Required? |
|---|---|---|
| Accessibility | Listen for the shortcut, list windows, focus/close/minimize them | Yes |
| Screen Recording | Live window previews | Only if you turn previews on |

TapTheTab makes **no network connections** and collects **no data**. It does not read
window contents unless you enable previews, and previews are kept in memory only.
See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Build from source

Requirements: macOS 13+, Xcode 16 (Swift 6 toolchain).

```bash
git clone https://github.com/memoliertorerr/tapthetab.git
cd tapthetab
make test      # unit tests for the core
make app       # builds dist/TapTheTab.app (ad-hoc signed)
make run       # opens it
```

The core logic (`Sources/TapTheTabCore`) is plain Swift and also builds and tests on Linux:
`swift test`.

## How it works

```
 ┌────────────────────── TapTheTab.app (macOS only) ──────────────────────┐
 │ HotkeyMonitor   CGEventTap: trigger detection, key capture while open  │
 │ WindowCatalog   CGWindowList + Accessibility → [SwitcherItem]          │
 │ FocusTracker    app activation + AX focus events → recency order       │
 │ WindowActions   raise / close / minimize / fullscreen / hide / quit    │
 │ ThumbnailService ScreenCaptureKit previews (opt-in, macOS 14+)         │
 │ UI              non-activating NSPanel + SwiftUI, Settings, Onboarding │
 └──────────────────────────────┬─────────────────────────────────────────┘
                                │ plain values
 ┌──────────────────────────────▼──── TapTheTabCore (any platform) ───────┐
 │ SwitcherSession (state machine) · FuzzyMatcher · RecencyTracker        │
 │ ItemFilter · KeyRouter · Shortcut · Configuration/ConfigStore · Grid   │
 └────────────────────────────────────────────────────────────────────────┘
```

More detail in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); what's next in
[docs/ROADMAP.md](docs/ROADMAP.md).

## Known limitations

- Windows on **other Spaces** are listed only when the app reports them through the
  Accessibility API; many apps only report windows on the current Space.
- Previews require macOS 14 or later; macOS 13 shows app icons.
- Secure input (password fields, some terminals with "Secure Keyboard Entry") blocks all
  global shortcuts, including this one.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 memoliertorerr.

TapTheTab is an independent project, inspired by AltTab and contains none of its code.
