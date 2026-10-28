# Changelog

All notable changes to TapTheTab are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/memoliertorerr/tapthetab/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/memoliertorerr/tapthetab/releases/tag/v0.1.0
