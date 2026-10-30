# TapTheTab — Roadmap and build plan

> TapTheTab is a keyboard-first macOS window switcher: every window, most recent first,
> type to search, release to switch. This document is the single source of truth for what
> is done, what is next, and what is deliberately not being built.
>
> **Explicitly NOT in scope** (see **Later**): telemetry of any kind, background network
> access other than the opt-in update check, window tiling beyond the existing actions,
> Mac App Store distribution (the sandbox forbids Accessibility control of other apps,
> active event taps and the private window-server calls a switcher needs).
>
> **Standing rule:** no data collection, ever; no network access except the opt-in update
> check (see **Decisions**). Read `AGENTS.md`.
>
> **Way of working:** one step = one commit, made only when verify is green. One phase =
> one pull request into `main`, merged after CI is green, then tagged as a release.

---

## Progress Tracker

| Step | Scope | Gate | Status |
|------|-------|------|--------|
| TT1 | Package skeleton, license, gitignore, core library (session, matcher, recency, filters, router, shortcuts, config, grid) | auto | ✅ done |
| TT2 | Core unit tests (200+), bug fixes found by them | auto | ✅ done |
| TT3 | macOS system layer: event tap, window catalog, focus tracking, actions, thumbnails, permissions, coordinator, menu bar | auto | ✅ done |
| TT4 | macOS UI layer: switcher panel, grid + list, settings, onboarding | auto | ✅ done |
| TT5 | CI (Linux core + macOS build), app bundle + icon, packaging, tag-driven release workflow, security docs | auto | ✅ done |
| TT6 | First green macOS CI build; fix compile errors surfaced there | checkpoint | ✅ done |
| TT7 | Release v0.1.0 | checkpoint | ✅ done |
| TT8 | Live window cache: per-app `AXObserver`s for window created / destroyed / title / minimized, so the list is correct the instant the panel opens | auto | ✅ done |
| TT9 | Shortcut recorder in Settings (any key + modifiers), conflict warnings | auto | ✅ done |
| TT10 | Frecency for search: remember which window was picked for a query prefix and boost it | auto | ✅ done |
| TT11 | Homebrew cask (in this repo, tapped by URL), documented in README | checkpoint | ✅ done |
| TT12 | Release v0.2.0 | checkpoint | ✅ done |
| TT13 | Localization (English, Italian, Turkish) and a VoiceOver pass over every UI string | auto | ✅ done |
| TT14 | `tapthetab://` URL scheme: open the switcher (optionally pre-filtered or scoped), open Settings — for Raycast/Alfred/Shortcuts | auto | ✅ done |
| TT15 | Large preview of the selected window (previews mode) | auto | ✅ done |
| TT16 | Core hygiene: shortcut-conflict advisor in the core (+ ⇧-reverse conflict), grid shrinks to fit width, diagnostics report | auto | ✅ done |
| TT17 | Release v0.3.0 | checkpoint | ✅ done |
| TT18 | Hardening audit of the macOS layer (stuck keys, focus, threading, leaks, ⌘⇥ restore) and fixes | auto | ✅ done |
| TT19 | Windows on other Spaces: research, then the most robust no-SIP approach behind a setting (off by default) | checkpoint | ✅ done |
| TT20 | Large-preview box stays reserved (icon placeholder) so the panel doesn't jump | auto | ✅ done |
| TT21 | Release v0.4.0 | checkpoint | ✅ done |
| TT22 | Screenshot renderer: the app draws the switcher and Settings from sample data (`--render-screenshots`), CI produces the PNGs, README shows them | auto | ✅ done |
| TT23 | Menu bar icon can be hidden (reopen the app to get Settings) | auto | ✅ done |
| TT24 | Release v0.5.0 | checkpoint | ✅ done |
| TT25 | Panel layout math (`SwitcherLayout`) moves into the core with tests | auto | ✅ done |
| TT26 | Rescue: `TapTheTab --restore-system-shortcuts` and `--reset-settings`; README Troubleshooting + Uninstall | auto | ✅ done |
| TT27 | Optional grouping of windows by app (`appearance.groupByApp`), apps ordered by recency | auto | ✅ done |
| TT27.1 | Performance: scoped catalog refreshes, cheaper opens, capture list reuse, one large preview in memory, timings in diagnostics *(added 2026-10-28)* | auto | ✅ done |
| TT27.2 | Virtual machines / guest apps: research and support where possible *(added 2026-10-28)* | auto | ✅ done |
| TT28 | Release v0.6.0 | checkpoint | ✅ done |
| TT29 | Liquid Glass look for the switcher (setting; Clear or Tinted like the system's; a similar translucent look before macOS 26); CI and releases build with Xcode 26 *(maintainer approved 2026-10-28)* | auto | ✅ done |
| TT30 | Large preview on its own card floating above the grid or list, smaller by default, with a size setting | auto | ✅ done |
| TT31 | Release v0.7.0 | checkpoint | ✅ done |
| TT31.1 | Fix: switching brought all of the app's windows forward; focus only the chosen window through the window server. Release v0.7.1 *(added 2026-10-28)* | checkpoint | ✅ done |
| TT32 | Fix for real: switching still raised every window of the app (v0.7.1 fell back after the window-server call); report the switch method in diagnostics | auto | ✅ done |
| TT33 | The two blocks (list, large preview) are separate windows that can be dragged while the switcher is open, stay on screen, remember their place; reset in Settings | auto | ✅ done |
| TT34 | Arc-style themes from Little Joan's theme engine: presets, custom colors, grain, strength; clearer Clear glass | auto | ✅ done |
| TT35 | Window thumbnails in list rows (taller rows), thumbnails and large preview as separate switches | auto | ✅ done |
| TT36 | Release v0.8.0 | checkpoint | ✅ done |
| TT37 | Developer ID signing + notarization: maintainer creates the certificate and API key and adds the six secrets (guide given 2026-10-29) | checkpoint | ✅ done (v0.9.0 signed and notarized, 2026-10-30) |
| TT38 | Animations (fade-in, sliding selection, preview reshaping), Reduce Motion respected | auto | ✅ done |
| TT39 | Quick select (modifier + 1–9) with badges | auto | ✅ done |
| TT40 | Window actions: next display, close app windows, pin apps first | auto | ✅ done |
| TT41 | Layout per shortcut; peek (⇧Space); Settings themed; menu bar icon styles; main block draggable anywhere | auto | ✅ done |
| TT42 | Release v0.9.0 | checkpoint | ✅ done |
| TT43 | Opt-in update checks and verified self-update (Homebrew installs: `brew upgrade`) *(maintainer approved 2026-10-30)* | auto | ⬜ todo |
| TT44 | Multiple displays: list the switcher's display first (option) | auto | ⬜ todo |
| TT45 | German, French, Spanish (and every new string in Italian and Turkish) | auto | ⬜ todo |
| TT46 | First-run tour of the keys, reopenable | auto | ⬜ todo |
| TT47 | CI smoke test, screenshot regression check, readable Wine/CrossOver app names | auto | ⬜ todo |
| TT48 | Website (GitHub Pages) with a demo animation; README refresh | auto | ⬜ todo |
| TT49 | Release v0.10.0 | checkpoint | ⬜ todo |

**Overall status:** v0.1.0–v0.9.0 released; the maintainer confirmed on macOS 26 that switching now brings only the chosen window forward. v0.9.0 released, the first release signed with a Developer ID and notarized. The maintainer tried v0.6.0 on a Mac (macOS 26) and likes it; phase 7 (v0.7.0, released) is a redesign from that feedback: the panel felt dark and opaque, and the large preview too big. Next: the maintainer's verdict on the glass and the preview size.

**Phases** — one pull request and one release each:
1. **TT1 → TT7** — v0.1.0, first usable release. Review focus: event tap safety (keys must
   never get stuck), window activation correctness, permissions onboarding.
2. **TT8 → TT12** — v0.2.0, speed and customisation.
3. **TT13 → TT17** — v0.3.0, reach, accessibility and automation.
4. **TT18 → TT21** — v0.4.0, hardening and other Spaces.
5. **TT22 → TT24** — v0.5.0, screenshots and conveniences.
6. **TT25 → TT28** — v0.6.0, testable layout, self-rescue, grouping by app.
7. **TT29 → TT31** — v0.7.0, Liquid Glass and a floating preview.
8. **TT32 → TT36** — v0.8.0, movable blocks, themes, list thumbnails, the real focus fix.
9. **TT37 → TT42** — v0.9.0, feel and power features; signing when the secrets exist.
10. **TT43 → TT49** — v0.10.0, updates, displays, languages, tour, website.

---

## How to run a phase

1. Branch from `main`: `git switch main && git pull && git switch -c feat/<phase-name>`.
2. For each step: implement, run verify, flip the row above to ✅ in the same commit.
3. Push the branch and open a pull request into `main` using the template below.
4. When CI is green, merge, bump `VERSION` + `CHANGELOG.md`, tag `vX.Y.Z` (or run the
   Release workflow), and check the release assets.

### PR description template

```markdown
## Phase <n>: <name>
Steps: TTa → TTb

| Step | Commit | Verify evidence |
|---|---|---|

### Notes
### Needs human check
- [ ] <what to try on a real Mac>
```

### Who verifies what

| Check | Who | Green looks like |
|---|---|---|
| `swift build && swift test` | automation, every step | 0 failures |
| CI `core-linux` + `macos` jobs | GitHub Actions | both green on the PR |
| Release workflow | GitHub Actions | release with `.dmg`, `.zip`, `SHA256SUMS.txt` |
| **Real-Mac behaviour** (shortcut, focus, permissions, previews) | **the maintainer** | ⌥⇥ opens within ~100 ms, tap switches to previous window, search works, ⌘⇥ restored after quit |

Unit tests cover the decision logic; only a person at a Mac can confirm the OS
integration, so every release step is a checkpoint.

## Ground rules

See `AGENTS.md`. In addition, for this plan:
- Stop and ask when a step needs a new dependency, a config-key rename, or a new private API.
- Never commit red; never weaken a test to get green.

### Rollback

| Situation | Command |
|---|---|
| Bad commit on a branch | `git revert <sha>` |
| Bad release | Mark the GitHub release as pre-release / delete its assets; ship a patch `vX.Y.(Z+1)` |
| ⌘⇥ stuck disabled after a crash | Relaunch and quit TapTheTab, or log out and back in |

---

## Step notes

### TT1–TT5 (2026-10-28)
- The core was written first as a contract; the macOS system layer, UI layer, tests and
  release pipeline were then built in parallel against it.
- Tests found and fixed: a fuzzy-match miss when jumping to a later word start, missing
  highlights for untitled windows, a `GridLayout` trap on zero/NaN sizes, and quarantine
  name collisions for two broken configs within one second.
- Config decoding became lenient per key (a single bad value no longer resets the whole
  file), saves became temp-file + rename with 0600 from the start, and the key router
  now ignores the trigger's own modifiers so search works with ⌘⇥ and ⌃⇥ triggers.

### TT6 (2026-10-28)
- The first macOS CI run compiled the whole app (Xcode 16.4, macOS 15.5 SDK, deployment
  target 13.0) for arm64 + x86_64 with no fixes needed, produced the icon, signed ad-hoc,
  and packaged the dmg and zip (~1.3 MB each).

### TT7 (2026-10-28)
- Released v0.1.0 through the Release workflow's manual trigger (it creates the tag); the
  dmg checksum was verified independently after download.

### TT8–TT11 (2026-10-28)
- Live list: `WindowWatcher` keeps one AXObserver per regular app (created, destroyed,
  title, minimized, hidden/shown, focus) and coalesces events into a catalog refresh.
- Search memory is in-memory only, keyed by window and by app; boost ≤ 90 points and
  only ever added to items that already match.
- Shortcut recorder uses a local key monitor in Settings; the tap still swallows active
  triggers, so recording a shortcut already in use needs a different one first.
- The cask lives in `Casks/` here and is tapped by URL, so no separate tap repository.
- CI now builds the macOS app with warnings as errors.

### TT13–TT16 (2026-10-28)
- Localization: English sentences are the keys (`L10n.tr`), tables live in
  `Resources/Localization/*.lproj` and are copied into the bundle by the build script;
  `scripts/check-strings.py` runs in CI. 132 keys in en/it/tr.
- `tapthetab://` links are parsed by the core `AutomationCommand` (strict; only opens UI).
- Large preview: layout reserves a box only when it fits (≥120 pt); the coordinator
  re-captures the selected window at the box's pixel size after an 80 ms debounce.
- Diagnostics: Settings → About → Copy Diagnostics (versions, permissions, counts,
  settings; no titles, names or bundle IDs).

### TT18 (2026-10-28)
- An independent read-through of the macOS layer found 13 issues (4 high); all fixed:
  missed modifier release after a tap timeout, fn-only triggers, AX calls without a
  timeout on window elements, permission revocation keeping a dead tap and ⌘⇥ disabled,
  ⌘⇥ left off after a crash, refresh storms from app-wide AX notifications, busy apps'
  windows vanishing and losing recency, live config reload resetting on a typo, links
  using TapTheTab as the "active app", stale triggers after pause, autorepeat leaking
  into the target window, recording an existing trigger, focus observers on apps not yet
  ready. Verified-correct areas are listed in the PR.
- Private functions moved to runtime lookup (`PrivateAPI.swift`).

### TT19 (2026-10-28)
- Implemented the research recommendation behind `filters.showOtherSpaces` (off by
  default): Space layout + per-Space window IDs from the window server, filtered with the
  public `CGWindowListCreateDescriptionFromArray`, 150 ms budget; focus via the
  front-process path with a 0x100-byte event record. Accessibility elements seen earlier
  are carried over between refreshes.
- Skipped the remote-token element scan: costly, unreliable, untestable here. Without an
  element, close/minimize/fullscreen on an other-Space window beep instead of acting.

### TT22–TT23 (2026-10-28)
- Screenshots: `ScreenshotRenderer` renders the real SwiftUI views with fictional sample
  windows (system app icons, synthetic previews) via `ImageRenderer`, composited on a
  gradient; Settings through an offscreen window. CI uploads them; the README copies are
  resized to ≤1600 px and quantized (~1.5 MB for 8 images). Settings toggles render grey
  because the offscreen window isn't key — acceptable.
- Menu bar icon can be hidden (`appearance.showMenuBarIcon`).

### TT25–TT27.2 (2026-10-28)
- Layout math moved to `PanelLayout` (core), verified bit-identical over ~1M inputs.
- Performance: scoped catalog refreshes (watcher reports which apps changed; opening
  re-asks only the frontmost app unless the list is >30 s old), ScreenCaptureKit window
  list reused for 1.5 s, one large preview kept in memory, refresh timings in diagnostics.
- Grouping by app keeps a quick tap on the previously used window.
- VM / Windows apps: see `docs/research/vm-windows.md`; `WindowAdmission` admits titled
  `AXUnknown` windows (Wine family) and drops untitled dialogs.
- Two compile errors reached CI this phase (a missed call site after a rename, a
  redeclared binding); both were caught there and fixed before merge.

### TT29–TT30 (2026-10-28)
- Builds moved to Xcode 26 (newest stable 26.x on the `macos-15` runner) so the app can use
  the system's Liquid Glass; the deployment target stays macOS 13. The glass code is behind
  `#if compiler(>=6.2)` and `#available(macOS 26.0, *)`, so Xcode 16 still builds the app.
- Apple offers no API to read the system's Clear/Tinted choice, so the app has its own:
  Clear = `Glass.clear` over a light dimming layer (Apple's advice for text on clear glass),
  Tinted = `Glass.regular`. Both follow Reduce Transparency and Increase Contrast.
- The window is now transparent; the main block and the preview card each draw a backdrop,
  and the window shadow is refreshed when the card changes shape.
- The preview's padding and gap add the same 20 pt as the old inset, so 100 % layouts are
  unchanged; the default is now 66 %.

### TT31.1 (2026-10-28)
- Found on a real Mac (macOS 26): picking one of three Terminal windows brought all three
  in front of the app that was active. Cause: making the app frontmost through its
  Accessibility attribute (and `NSRunningApplication.activate`) raises every window of the
  app. Every switch now uses the window-server path that was only used for other Spaces
  (front process with the window, without the all-windows flag, plus the make-key record),
  as other switchers do; the old public path is the fallback if the functions disappear.

### TT32–TT35 (2026-10-29)
- v0.7.1 still raised all of an app's windows on a real Mac. Most likely cause: the code
  checked `_SLPSSetFrontProcessWithOptions`'s return value and fell back to the public
  path (which raises everything) when it was not zero; AltTab and yabai ignore that value.
  Now it is only reported (Copy Diagnostics → Private APIs → Last switch), and the public
  fallback runs only when the functions are missing. Unconfirmed until tried on a Mac.
- The main block and the preview card are two `NSPanel`s; `PanelPlacement` (core) places
  them (default: together in the middle, the card following the main block, below it if
  there is no room above) and clamps drags to the screen. Positions are stored as
  fractions of the visible frame (`appearance.panelPosition` / `previewPosition`).
- Themes are Little Joan's engine ported to Swift (`ColorMath`, `ColorTheme`,
  `GrainTexture`), checked against its TypeScript output for every preset.

### TT37–TT41 (2026-10-29)
- Icon variants for the app itself were dropped: changing a signed app's icon at run time
  writes into the bundle and breaks its signature. The menu bar icon (what is visible for
  a menu bar app) got styles instead.
- Peek is a still capture shown in its own panel above the switcher (no window is raised,
  so nothing changes the window order); it needs Screen Recording.
- Quick select uses ⌘ unless the trigger itself holds ⌘ (then ⌃, then ⌥), so plain digits
  keep searching.

## Deferred follow-ups
- ~~Grid ↓ over a gap in a partial last row wraps to the top~~ — fixed in TT10's phase.
- `GridLayout` shrinks to fit height only; very large card sizes on tiny screens can
  overflow horizontally.
- ~~`.activeApp` with a windowless frontmost app shows an empty panel~~ — fixed in phase 2.
- ~~Search highlights only the higher-scoring field~~ — contiguous hits in both fields are
  highlighted since phase 2.
- ~~`ShortcutAdvisor` lives in the UI layer~~ — replaced by core `ShortcutConflicts` (phase 3).
- ~~Warn about ⇧-reverse clashes~~ — done in phase 3.
- `GridLayout` can still exceed a screen narrower than one card at minimum scale (rare).
- Other Spaces: verify window-list option `0x2` excludes minimized windows; consider the
  remote-token scan only if real-Mac feedback shows actions on other-Space windows matter.
- ~~The large preview hides for items without a thumbnail~~ — the box is reserved and shows
  the app icon since TT20.

## Landmines
- ⌘⇥ never reaches an event tap; it is a Window Server symbolic hotkey (see ARCHITECTURE).
- Ad-hoc signed builds (local builds, releases up to v0.8.0) get a new code signature every
  build, so macOS may silently drop the Accessibility grant after an update. Releases are
  Developer ID signed since v0.9.0.
- Signing secrets: `MACOS_CERT_PASSWORD` is the password chosen when exporting the .p12
  from Keychain Access (not a GitHub or Apple ID password); `NOTARY_ISSUER_ID` is the UUID
  at the top of App Store Connect's Team Keys page (not the Key ID).
- `CGWindowListCreateImage` is obsoleted in the macOS 15 SDK; use ScreenCaptureKit.
- AX calls are synchronous IPC; one hung app can stall enumeration without
  `AXUIElementSetMessagingTimeout`.

## Decisions

- **Update checks (2026-10-30, maintainer):** an exception to "no network". Off by default;
  when on, once a day one HTTPS GET to GitHub's "latest release" API, no identifiers beyond
  a `User-Agent` with the app version, no cookies or cache. "Check for Updates…" in the menu
  does the same once, on request. Installing verifies the dmg's SHA-256 against the release's
  `SHA256SUMS.txt` and the new app's Developer ID signature (same team ID and bundle ID as
  the running app) before replacing the bundle; Homebrew installs are pointed at
  `brew upgrade --cask tapthetab` instead. No third-party updater framework.
- **Mac App Store (2026-10-30):** not possible without dropping window switching; direct
  distribution (Developer ID + notarization) and Homebrew instead.

## Later (designed, deliberately not built)
- Plugin/scripting hooks (e.g. a URL scheme to open the switcher pre-filtered).
