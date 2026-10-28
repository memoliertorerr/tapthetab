# Changelog

All notable changes to TapTheTab are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/memoliertorerr/tapthetab/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/memoliertorerr/tapthetab/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/memoliertorerr/tapthetab/releases/tag/v0.1.0
