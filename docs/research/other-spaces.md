# Research: windows on other Spaces (2026-10-28)

Why: the Accessibility API only reports windows on the current Space for most apps
(since macOS 12.2), so TapTheTab misses windows on other Spaces and in fullscreen
Spaces. This note records how other tools solve it and what TapTheTab should do.
Sources were read to learn *which* OS functions are used; no GPL code was copied.

## Recommendation (no SIP changes)

**List** windows from the window server, use Accessibility only for elements to act on:

1. `CGSCopyManagedDisplaySpaces(cid)` → every Space per display (including fullscreen
   Spaces) and each display's current Space.
2. `CGSCopyWindowsWithOptionsAndTags(cid, 0, [spaceID], options, &set, &clear)` per
   Space → window IDs front-to-back, which also tells us each window's Space.
3. Filter with the public `CGWindowListCreateDescriptionFromArray`: layer 0, alpha > 0,
   roughly ≥ 50×50, owner is a regular app.
4. Join to AX elements via `_AXUIElementGetWindow` over `kAXWindowsAttribute`.
5. For windows still missing an element, optionally build one with
   `_AXUIElementCreateWithRemoteToken` (20-byte token: pid, 0, "coco", 64-bit element id),
   scanning ids under a strict time budget off the main thread, caching results and
   treating "not found" as normal.

**Focus** a window on another Space: `GetProcessForPID` → `_SLPSSetFrontProcessWithOptions(psn,
wid, 0x200)` → two `SLPSPostEventRecordTo` posts with a zeroed 0x100-byte record (the
0xf8-byte variant crashes on macOS 14) → `kAXRaiseAction`. This also switches Space.
Known side effects: other Spaces' front-app record can change; System Settings may
bounce back to its previous Space.

**Fail soft**: resolve every private symbol with `dlsym(RTLD_DEFAULT, …)` at runtime, not
`@_silgen_name` (a strong link-time binding makes dyld refuse to launch the whole app if
Apple removes the symbol). Expose capability flags, report them in diagnostics, put
everything behind a setting that is off by default.

## Public-API fallback

`CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements])` lists off-Space
windows (id + pid), but cannot tell "other Space" from minimized/hidden, has no Space
id, needs Screen Recording for `kCGWindowName` (titles), and gives no AX element (focus
means activating the app). Keeping AX elements seen earlier (before the user left that
Space) may help; validity after leaving a Space is untested.

## Out of scope (needs SIP disabled)

Creating/moving/focusing Spaces directly, moving windows between Spaces on macOS 15+,
window layers/opacity — all require yabai's Dock scripting addition.

## Stability notes

| macOS | Change |
|---|---|
| 12.2 | AX stopped returning other-Space windows. |
| 14.x | `SLPSPostEventRecordTo` with a 0xf8-byte buffer aborts; use 0x100 bytes. |
| 14 | `activate` became cooperative/advisory. |
| 14.5 / 15 | Moving windows to another Space from a normal process stopped working. |
| 26 | Window owner names need Screen Recording; read APIs above still work. |

## Sources

- yabai (MIT): https://github.com/asmvik/yabai — `src/misc/extern.h`, `src/space.c`,
  `src/window_manager.c`, issues #1324, #2575, CHANGELOG
- Hammerspoon (MIT) `extensions/spaces/libspaces.m`
- Amethyst (MIT) `Amethyst/Model/Window.swift`
- AltTab (GPL-3.0, approach only) issues #1324, commit 2cd8b96
- Apple: `CGWindowListOption.optionAll`, `NSRunningApplication.activate(options:)`,
  cooperative activation; Developer Forums threads 126860 and 839069
- paneru issue #123; Swindler issue #26; macos-defaults `AppleSpacesSwitchOnActivate`
