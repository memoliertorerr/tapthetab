# Changelog

All notable changes to TapTheTab are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.0] - 2026-10-29

### Added

- Move the switcher: while it is open, drag the window list or the large preview anywhere on the screen. TapTheTab remembers where; Settings → Appearance → Reset Position puts them back.
- Themes, inspired by Arc: a soft gradient with grain over the switcher's glass. Eleven presets or up to three colors of your own, with color, grain and strength sliders (Settings → Appearance → Theme).
- Window thumbnails in the list style: with previews on, each row shows a live thumbnail of its window (app icon as a badge) in a taller row. Thumbnails and the large preview can each be turned off.
- Copy Diagnostics says how the last switch brought its window forward.

### Fixed

- Switching to a window could still bring all of the app's windows forward: the window-server call that brings only the chosen window forward was treated as failed when it returned a non-zero status, and the fallback then raised every window of the app.

### Changed

- Clear Liquid Glass is more see-through (no extra dimming layer).
- The large preview is a separate floating window from the list.

## [0.7.1] - 2026-10-28

### Fixed

- Switching to a window no longer brings the app's other windows forward too: only the window you picked comes to the front, like clicking it.

## [0.7.0] - 2026-10-28

### Added

- Liquid Glass look for the switcher (Settings → Appearance → Liquid Glass), on by default: Clear (more see-through) or Tinted (frosted, more contrast), like the macOS setting. macOS 26 uses the system's glass; earlier versions get a similar translucent look. Turn it off for the classic dark panel.
- Size setting for the large preview: 50 %, 66 %, 75 % or 100 % (`appearance.largePreviewPercent`).

### Changed

- The large preview of the selected window floats on its own card above the switcher, shaped like the window, and is smaller by default (66 % of its previous size).
- Built with Xcode 26; still runs on macOS 13 and later.

## [0.6.0] - 2026-10-28

### Added

- Rescue options for the command line: `--restore-system-shortcuts` turns ⌘⇥ back on if it stayed off, `--reset-settings` starts over with defaults (the old `config.json` is kept); also `--version` and `--help`.
- README sections on troubleshooting and uninstalling.
- Optional grouping of windows by app (Settings → Appearance), with a heading per app in the list style. A quick ⌥⇥ still goes to the window you used before.
- Copy Diagnostics reports how long the last window-list refreshes took, and how many windows were left out by window type.
- Windows from CrossOver, Wine, Whisky and Game Porting Toolkit that draw their own title bar now appear in the switcher. Windows kept above the normal window layer count as on screen.

### Fixed

- Untitled dialogs (pop-ups, toasts) no longer appear as switcher entries.

### Changed

- Faster and lighter: when windows change, only that app is asked again; opening the switcher re-asks only the frontmost app; previews reuse the screen-capture window list; large previews are no longer kept for every window you selected (this could add up to over 100 MB).

## [0.5.0] - 2026-10-28

### Added

- Screenshots in the README, rendered by the app itself from fictional sample windows (`TapTheTab --render-screenshots <folder>`, `make screenshots`) and refreshed by CI.

- Option to hide the menu bar icon (Settings → Appearance). Open TapTheTab again, or use `tapthetab://settings`, to get back to Settings.

## [0.4.0] - 2026-10-28

### Added

- **Windows on other Spaces** (opt-in): Settings → Filters → *Show windows on other Spaces*. Windows on other Spaces and fullscreen Spaces are listed after the current ones, and picking one switches to its Space. Uses private macOS interfaces and switches itself off if they are unavailable.
- Copy Diagnostics now reports whether those interfaces are available.

### Fixed

- The keyboard can no longer stay captured after a missed modifier release (for example while macOS briefly paused TapTheTab), on sleep, screen lock or user switch.
- If the Accessibility permission is removed, TapTheTab stops capturing keys, gives ⌘⇥ back to macOS and resumes once the permission returns.
- ⌘⇥ is turned back on at the next launch if TapTheTab crashed while owning it.
- Holding ⇥ after releasing ⌥ no longer types tabs into the window you switched to.
- A busy or beachballing app no longer stalls TapTheTab (every Accessibility call is capped) or disappears from the switcher.
- A half-saved or mistyped `config.json` no longer resets your settings while TapTheTab runs.
- `tapthetab://switch?scope=activeApp` shows the app you came from, and dismissing returns focus to it.
- Recording a shortcut that TapTheTab already uses works instead of opening the switcher.
- A shortcut needs ⌘, ⌥ or ⌃; an fn-only shortcut in `config.json` used to capture every ⇥ press.
- The large preview keeps its place (showing the app icon) for windows without a preview, so the panel no longer jumps.
- Much less background work: window changes are coalesced and app-wide title noise is ignored.
- Private macOS functions are looked up at runtime, so a future macOS removing one can't stop TapTheTab from launching.

## [0.3.0] - 2026-10-28

### Added

- Large preview of the selected window when previews are on.
- Settings → About → **Copy Diagnostics**: versions, permissions, counts and settings for bug reports — no window titles or app names.
- Italian and Turkish translations, and VoiceOver labels throughout.
- `tapthetab://` links: `tapthetab://switch?query=…&scope=…` opens the switcher already searching, `tapthetab://settings` opens Settings. Handy from Raycast, Alfred, Shortcuts or `open` in a terminal.
- Settings warns when a shortcut clashes with a macOS shortcut or with another trigger plus ⇧.

### Changed

- Grid cards also shrink to fit narrow screens.

## [0.2.0] - 2026-10-28

### Added

- Search remembers what you picked: choose a window after typing `sl` and it ranks first the next time you type `s` or `sl`. Kept in memory only, never written to disk.
- Record any shortcut in Settings → General (click the shortcut, press the new one). Common system shortcuts get a warning; presets are still one click away.
- Live window list: TapTheTab now watches each app's windows, so the switcher opens with an up-to-date list and drops windows closed elsewhere while it is open.
- Homebrew: `brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab && brew install --cask tapthetab`.
- "Check for Updates…" in the menu bar and in Settings → About. It only opens the releases page; TapTheTab still never goes online itself.

### Changed

- The switcher keeps its top edge in place while you type instead of re-centring on every keystroke.
- Hovering no longer steals the selection right after you move it with the keyboard.
- ↓ from a card above a gap in the last grid row selects the last card instead of jumping to the top.
- Matches are highlighted in both the title and the app name when both contain the search.

### Fixed

- The same-app switcher (⌥`) shows the app itself when it has no windows, instead of an empty panel.

## [0.1.0] - 2026-10-28

### Added

- First release of TapTheTab, a keyboard-first window switcher for macOS 13 and later.
- ⌥⇥ (Option-Tab) window switcher with live search: start typing to filter windows by app or title.
- ⌥` (Option-backtick) to cycle through the windows of the frontmost app only.
- Keyboard actions on the selected window: close, minimize, toggle full screen, hide the app, and quit the app.
- Grid and list layouts.
- Optional live window previews (needs the Screen Recording permission; everything else works without it).
- JSON configuration with safe defaults; an unreadable config file is moved aside (never deleted) and defaults are used until it is fixed.
- Menu bar app with a settings window and an optional launch-at-login toggle.
- Privacy by design: no network access and no telemetry. Settings stay on your Mac.

[Unreleased]: https://github.com/memoliertorerr/tapthetab/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/memoliertorerr/tapthetab/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/memoliertorerr/tapthetab/releases/tag/v0.1.0
