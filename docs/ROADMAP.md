# TapTheTab — Roadmap and build plan

> TapTheTab is a keyboard-first macOS window switcher: every window, most recent first,
> type to search, release to switch. This document is the single source of truth for what
> is done, what is next, and what is deliberately not being built.
>
> **Explicitly NOT in scope** (see **Later**): auto-update over the network, telemetry of
> any kind, window tiling/management beyond focus/close/minimize/fullscreen/hide/quit,
> Mac App Store distribution (sandboxing makes a switcher impossible).
>
> **Standing rule:** no network access and no data collection, ever. Read `AGENTS.md`.
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
| TT18 | Hardening audit of the macOS layer (stuck keys, focus, threading, leaks, ⌘⇥ restore) and fixes | auto | ⬜ todo |
| TT19 | Windows on other Spaces: research, then the most robust no-SIP approach behind a setting (off by default) | checkpoint | ⬜ todo |
| TT20 | Large-preview box stays reserved (icon placeholder) so the panel doesn't jump | auto | ⬜ todo |
| TT21 | Release v0.4.0 | checkpoint | ⬜ todo |

**Overall status:** v0.1.0, v0.2.0 and v0.3.0 released. Phase 4 (v0.4.0) in progress: hardening before the first real-Mac feedback, then other Spaces.

**Phases** — one pull request and one release each:
1. **TT1 → TT7** — v0.1.0, first usable release. Review focus: event tap safety (keys must
   never get stuck), window activation correctness, permissions onboarding.
2. **TT8 → TT12** — v0.2.0, speed and customisation.
3. **TT13 → TT17** — v0.3.0, reach, accessibility and automation.
4. **TT18 → TT21** — v0.4.0, hardening and other Spaces.

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
- The large preview hides for items without a thumbnail, so the panel height changes while
  arrowing past minimized/hidden items; consider reserving the box and showing the icon.

## Landmines
- ⌘⇥ never reaches an event tap; it is a Window Server symbolic hotkey (see ARCHITECTURE).
- Ad-hoc signed builds get a new code signature every build, so macOS may silently drop
  the Accessibility grant after an update. Document it; fix for real with Developer ID.
- `CGWindowListCreateImage` is obsoleted in the macOS 15 SDK; use ScreenCaptureKit.
- AX calls are synchronous IPC; one hung app can stall enumeration without
  `AXUIElementSetMessagingTimeout`.

## Later (designed, deliberately not built)
- Developer ID signing + notarization: the release workflow already supports it when the
  signing secrets are added; nothing to build, only secrets to provide.
- Update checks: only as a manual "Check for updates" link that opens the releases page,
  never a background request.
- Plugin/scripting hooks (e.g. a URL scheme to open the switcher pre-filtered).
