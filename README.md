<div align="center">

# TapTheTab

**Every window, one tap away.** A fast, keyboard-first window switcher for macOS.

Hold <kbd>⌥</kbd>, tap <kbd>⇥</kbd>, see every window. Type to search. Let go to switch.

**[Website](https://memoliertorerr.github.io/tapthetab/)** · **[Download](https://github.com/memoliertorerr/tapthetab/releases/latest)** · **[Changelog](CHANGELOG.md)**

[![CI](https://github.com/memoliertorerr/tapthetab/actions/workflows/ci.yml/badge.svg)](https://github.com/memoliertorerr/tapthetab/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/memoliertorerr/tapthetab?include_prereleases&sort=semver)](https://github.com/memoliertorerr/tapthetab/releases)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

<p align="center">
  <img alt="Animation: the switcher lists fourteen windows in a grid and the selection moves from card to card; typing “re” narrows a list to the matching windows; the selection then moves down a list with window thumbnails on a purple theme" src="docs/images/demo.png" width="800">
</p>

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
2. **Privacy by default.** No telemetry, no analytics, ever, and no network access unless
   you turn on update checks (off by default; see [Privacy](#permissions-and-privacy)).
   Window previews are opt-in, so out of the box TapTheTab needs only the Accessibility
   permission, not Screen Recording.
3. **Small and hackable.** A plain-text JSON config, a pure-Swift core with unit tests that
   run on any platform, and a thin macOS layer on top.

## Features

<table>
  <tr>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/switcher-grid-dark.png">
        <img alt="The switcher showing fourteen windows from different apps in a grid, the second one selected" src="docs/images/switcher-grid-light.png">
      </picture>
      <p align="center"><sub>Every window, most recent first</sub></p>
    </td>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/switcher-search-dark.png">
        <img alt="List layout while searching for 're': matching letters are highlighted in titles and app names" src="docs/images/switcher-search-light.png">
      </picture>
      <p align="center"><sub>Type to search — matches are highlighted</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/switcher-previews-dark.png">
        <img alt="Grid with live window previews and a large preview of the selected window" src="docs/images/switcher-previews-light.png">
      </picture>
      <p align="center"><sub>Optional live previews</sub></p>
    </td>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/switcher-themed-dark.png">
        <img alt="List layout on the Dusk theme: each row shows a live thumbnail of its window with the app icon as a badge" src="docs/images/switcher-themed-light.png">
      </picture>
      <p align="center"><sub>Themes and window thumbnails in the list</sub></p>
    </td>
  </tr>
</table>

<sub>The screenshots and the animation are rendered by the app itself from fictional
sample windows (`make screenshots`, `make demo`), so they always match the current UI.</sub>


- **All windows, most recent first** — including minimized windows and hidden apps
  (each can be filtered out).
- **Type to search** — fuzzy, case- and accent-insensitive, matches titles and app names,
  highlights what matched, and remembers what you picked so it ranks first next time.
- **Same-app switcher** — <kbd>⌥</kbd><kbd>\`</kbd> cycles only the frontmost app's windows.
- **Act without switching** — close, minimize, fullscreen, hide or quit the selected
  window's app straight from the switcher.
- **Quick tap = previous window** — a tap under the show delay (90 ms by default) switches
  back without the panel ever flashing.
- **Group by app** if you like — apps in recency order, each app's windows together.
- **Several displays** — the switcher can list the windows of the display it opens on
  first (option).
- **Liquid Glass** — the panel is see-through glass on macOS 26 (Clear or Tinted, like the
  system setting), a similar translucent look on earlier versions, or the classic dark panel.
- **Themes** — Arc-style gradients with grain: thirteen presets, including Omarch Jade and Omarch Night, or your own colors.
- **Move it** — drag the list or the large preview anywhere while the switcher is open;
  it remembers where.
- **Quick select, peek, pin** — ⌘1–9 jumps to a window, ⇧Space peeks at it full size,
  ⇧P pins an app to the top; ⇧D sends a window to your other display.
- **A layout per shortcut** — e.g. ⌥⇥ as a grid and ⌥\` as a list.
- **Grid or list layout**, three sizes, light/dark/system theme, shows on the display with
  your mouse (or the active window, or the main display).
- **Optional live previews** (macOS 14+, needs Screen Recording): window thumbnails in the
  grid and the list, and a large preview of the selected window on its own floating card
  (25–150 % size, with presets and fine adjustment; limited to available screen space).
- **First-run tour** — a short walk through the keys the first time you run it; reopen it
  from the menu bar menu or Settings → About → Show Tour…. Settings → About also has
  Quit TapTheTab, which restores any system shortcuts the app took over.
- **Speaks your language** — English, Italian, Turkish, German, French and Spanish, with
  VoiceOver support.
- **Scriptable** — `tapthetab://` links open the switcher pre-filtered from launchers,
  Shortcuts or the terminal (see [Automation](#automation)).
- **Use ⌘⇥ if you like** — TapTheTab can take over the system shortcut while it runs and
  hands it back when it quits.
- **Any shortcut you like** — record one in Settings, or edit the config.
- **Always current** — window changes are watched live, so the list is right the moment
  the switcher opens.
- **Update checks, if you want them** — off by default (see
  [Privacy](#permissions-and-privacy)); Homebrew installs update with `brew upgrade`.
- **Menu bar app** with Settings, pause/resume and launch at login.
- **Hand-editable config** that is reloaded live when you save it.

## Omarch themes

Choose **Settings → Appearance → Theme → Omarch Jade** or **Omarch Night**. Their colors
come from Omarchy’s [Osaka Jade](https://github.com/omacom/omarchy/blob/afa2839a5ac7bf1c2da4f49649b8dbd0f83f7f12/themes/osaka-jade/colors.toml)
and [Tokyo Night](https://github.com/omacom/omarchy/blob/afa2839a5ac7bf1c2da4f49649b8dbd0f83f7f12/themes/tokyo-night/colors.toml)
palettes, adapted to TapTheTab’s glass and readable light/dark gradients.

<table>
  <tr>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/omarch-jade-dark.png">
        <img alt="Omarch Jade: the window list with a jade green, turquoise and warm cream theme" src="docs/images/omarch-jade-light.png">
      </picture>
      <p align="center"><sub>Omarch Jade</sub></p>
    </td>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/omarch-night-dark.png">
        <img alt="Omarch Night: the window list with a blue and lavender theme" src="docs/images/omarch-night-light.png">
      </picture>
      <p align="center"><sub>Omarch Night</sub></p>
    </td>
  </tr>
</table>

<sub>Rendered by TapTheTab from fictional windows (`make theme-screenshots`). Color,
Grain and Strength remain adjustable; the images follow your GitHub light/dark theme.</sub>

## Install

**Homebrew**

```bash
brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab
brew install --cask tapthetab
```

Update later with `brew upgrade`.

**Manually**

1. Download `TapTheTab-<version>.dmg` (or `.zip`) from the
   [latest release](https://github.com/memoliertorerr/tapthetab/releases/latest).
2. Drag **TapTheTab** into **Applications** and open it.
3. Grant **Accessibility** when asked (System Settings → Privacy & Security →
   Accessibility). That's the only required permission.

> [!NOTE]
> Releases are signed with a Developer ID and notarized by Apple (since v0.9.0), so they
> open without a Gatekeeper warning and keep the Accessibility permission across updates.
> Each release lists SHA-256 checksums in `SHA256SUMS.txt`.

> [!TIP]
> Coming from v0.8.0 or earlier (ad-hoc signed)? macOS sees the signed app as new once: if
> the shortcut does nothing after updating, remove TapTheTab from the Accessibility list
> and add it back. Later updates keep the permission.

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
| <kbd>⇧</kbd><kbd>X</kbd> | Close all of the app's windows |
| <kbd>⇧</kbd><kbd>D</kbd> | Move the window to the next display |
| <kbd>⇧</kbd><kbd>P</kbd> | Pin or unpin the app (pinned apps' windows come first) |
| <kbd>⌘</kbd><kbd>1</kbd>…<kbd>9</kbd> | Switch straight to that window (<kbd>⌃</kbd> instead of <kbd>⌘</kbd> when your shortcut uses <kbd>⌘</kbd>) |
| <kbd>⇧</kbd><kbd>Space</kbd> | Peek: show the selected window full size where it is; again to go back (needs Screen Recording) |
| <kbd>⌥</kbd><kbd>\`</kbd> | Same thing, but only the current app's windows |

The mouse works too: hover to select, click to switch, click outside to dismiss.

## Configuration

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-general-dark.png">
    <img alt="TapTheTab Settings, General tab: launch at login, shortcut recorder rows and behaviour toggles" src="docs/images/settings-general-light.png" width="460">
  </picture>
</p>

Everything in Settings is stored in
`~/Library/Application Support/TapTheTab/config.json` (owner-only permissions). Edit it
by hand if you prefer — TapTheTab reloads it as soon as you save. Unknown or missing keys
fall back to defaults, and a file that can't be read is set aside as
`config.invalid-<timestamp>.json` instead of being overwritten.

Each shortcut also has a **Desktops** choice in Settings → General. **Default** follows
Filters; other choices apply only to that shortcut. For example, use all desktops with
⌘Tab and the current desktop only with ⌥Tab. In JSON, set `desktopCoverage` on a trigger
to `currentDesktop`, `automatic`, or `allDesktops`; omit it to inherit. Choosing all
desktops opts into the existing private macOS listing. Menu and URL launches follow
Filters. After changing coverage, allow the background list refresh to complete.

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
    "wrapAround": true,
    "checkForUpdates": false
  },
  "appearance": {
    "style": "grid",
    "size": "medium",
    "showPreviews": false,
    "windowThumbnails": true,
    "showLargePreview": true,
    "largePreviewPercent": 66,
    "showAppName": true,
    "showMenuBarIcon": true,
    "groupByApp": false,
    "theme": "system",
    "liquidGlass": true,
    "glassStyle": "clear",
    "colorTheme": { "preset": "dusk", "colors": ["#9d8fd0", "#e0a2a0"], "intensity": 0.6, "grain": 0.3, "opacity": 0.55 },
    "placement": "mouse",
    "showDelayMilliseconds": 90
  },
  "filters": {
    "showMinimized": true,
    "showHiddenApps": true,
    "showWindowlessApps": false,
    "currentSpaceOnly": false,
    "currentDisplayOnly": false,
    "showOtherSpaces": false,
    "excludedBundleIDs": ["com.apple.finder"]
  }
}
```

- **Triggers** can carry their own `"style": "grid"` or `"list"`.
- **Updates:** `checkForUpdates` is `false` unless you turn it on (Settings, or here).
- **Shortcuts** are written as `modifier+…+key`, e.g. `command+tab`, `ctrl+shift+space`,
  `option+grave`. A shortcut needs at least one of ⌘ ⌥ ⌃ fn.
- **Scopes:** `allWindows`, `activeApp` (the frontmost app's windows) and `apps` (one
  entry per app, like ⌘⇥).
- **Styles:** `grid` or `list`. **Sizes:** `small`, `medium`, `large`.
  **Placement:** `mouse`, `activeWindow`, `main`.
- **Look:** `liquidGlass` `true` (glass) or `false` (classic dark panel); `glassStyle`
  `clear` (more see-through) or `tinted` (frosted, more contrast).
  `largePreviewPercent` (25–150) sizes the large preview.
- **Theme:** `colorTheme.preset` is `none`, a preset (`mist`, `sand`, `sage`, `lagoon`,
  `dusk`, `ember`, `orchid`, `glacier`, `meadow`, `berry`, `graphite`, `omarch-jade`, `omarch-night`) or `custom` (1–3
  `colors`); `intensity`, `grain` and `opacity` go from 0 to 1.
- **Position:** `panelPosition` and `previewPosition` are set when you drag the switcher
  (fractions of the screen); remove them, or use Reset Position, to centre it again.

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
| Network (outgoing) | The daily check for a newer release, if you turn update checks on | No (off by default) |

**No telemetry. No network access unless you turn on automatic update checks** (off by
default): then once a day TapTheTab asks GitHub for the latest release; nothing about you
or your Mac is sent beyond that request. Updates are verified (Developer ID signature and
checksum) before installing; Homebrew installs update with `brew upgrade`.

TapTheTab collects **no data**. It does not read window contents unless you enable
previews, and previews are kept in memory only. See [SECURITY.md](SECURITY.md) to report a
vulnerability.

## Build from source

Developers can run `make soak` for a reproducible synthetic workload; see [performance checks](docs/PERFORMANCE.md) for commands and measurement limits.


Requirements: macOS 13+, Xcode 26 (Swift 6.2 toolchain). Xcode 16 still builds the app,
without the system Liquid Glass (the similar translucent look is used instead).

```bash
git clone https://github.com/memoliertorerr/tapthetab.git
cd tapthetab
make test      # unit tests for the core
make app       # builds dist/TapTheTab.app (ad-hoc signed)
make run       # opens it
make screenshots demo   # renders the pictures above from sample data
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

## Virtual machines and Windows apps

- **Parallels Desktop in Coherence mode:** each Windows app shows up as its own entry, with
  its own name and icon.
- **CrossOver, Wine, Whisky, Game Porting Toolkit:** each Windows program shows up as its
  own entry (from 0.6.0, including windows that draw their own title bar).
- **UTM, VirtualBox, VMware Fusion, Parallels in window mode, macOS VMs:** you see the VM
  window. The apps inside it are pixels inside that one window — no Mac app can tell them
  apart. Use the guest's own switcher (Alt+Tab in Windows) once you're inside.

Something missing? Copy Diagnostics (Settings → About) lists how many windows were left
out and why, without names.

## Known limitations

- Settings → Filters → **Desktops and full-screen apps** controls which desktops are
  included. The default, *Current desktop, more from full screen*, keeps previously seen
  desktop windows available inside a full-screen app and lists apps whose windows macOS
  cannot expose. *Current desktop only* stays strictly on the current Space.
  *All desktops and full-screen apps* (`"showOtherSpaces": true`) lists individual windows
  across every Space, including desktops you have not visited. That option uses private
  macOS interfaces, stays off by default, and falls back quietly if those interfaces are
  unavailable. Without Screen Recording, other-Space windows may show the app name until
  you visit their Space.
- While the switcher is open, the selected large preview refreshes about every two
  seconds. Capture failures back off and eventually replace stale images with the app
  icon. An app that stops drawing off-screen can still supply its last frame.
- Previews require macOS 14 or later; macOS 13 shows app icons.
- Secure input (password fields, some terminals with "Secure Keyboard Entry") blocks all
  global shortcuts, including this one.

## Troubleshooting

**The shortcut does nothing.** Open System Settings → Privacy & Security → Accessibility
and make sure TapTheTab is listed and on. After the first update from an ad-hoc signed
build (v0.8.0 or earlier) or with a build you made yourself, macOS can drop the permission
silently: remove TapTheTab from the list with **−** and add it again.

**⌘⇥ stopped working after TapTheTab crashed or was deleted while using ⌘⇥.** Run:

```bash
/Applications/TapTheTab.app/Contents/MacOS/TapTheTab --restore-system-shortcuts
```

(Logging out and back in also restores it.)

**Settings are in a bad state.** Quit TapTheTab and run the line below; your old
`config.json` is kept next to the new one.

```bash
/Applications/TapTheTab.app/Contents/MacOS/TapTheTab --reset-settings
```

**Something else.** Settings → About → **Copy Diagnostics** and paste it into a
[new issue](https://github.com/memoliertorerr/tapthetab/issues/new/choose). It contains
versions, permissions, counts and settings — no window titles or app names.

## Uninstall

1. Quit TapTheTab from its menu (this hands ⌘⇥ back to macOS if you used it).
2. Delete `/Applications/TapTheTab.app` (or `brew uninstall --cask --zap tapthetab`).
3. Optionally delete `~/Library/Application Support/TapTheTab` and remove TapTheTab from
   System Settings → Privacy & Security → Accessibility (and Screen Recording).

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 memoliertorerr.

TapTheTab is an independent project, inspired by AltTab and contains none of its code.
