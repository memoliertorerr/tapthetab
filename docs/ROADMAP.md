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
| TT6 | First green macOS CI build; fix compile errors surfaced there | checkpoint | ⬜ todo |
| TT7 | Release v0.1.0 | checkpoint | ⬜ todo |
| TT8 | Live window cache: per-app `AXObserver`s for window created / destroyed / title / minimized, so the list is correct the instant the panel opens | auto | ⬜ todo |
| TT9 | Shortcut recorder in Settings (any key + modifiers), conflict warnings | auto | ⬜ todo |
| TT10 | Frecency for search: remember which window was picked for a query prefix and boost it | auto | ⬜ todo |
| TT11 | Homebrew cask in a tap repo, documented in README | checkpoint | ⬜ todo |
| TT12 | Release v0.2.0 | checkpoint | ⬜ todo |
| TT13 | Windows on other Spaces (private CGS space APIs behind a setting), Space badge on cards | auto | ⬜ todo |
| TT14 | Large preview of the selected window on hover/selection (previews mode) | auto | ⬜ todo |
| TT15 | VoiceOver pass and localization scaffolding (English + Italian + Turkish) | checkpoint | ⬜ todo |
| TT16 | Release v0.3.0 | checkpoint | ⬜ todo |

**Overall status:** phase 1 code complete; waiting on the first macOS CI run (TT6).

**Phases** — one pull request and one release each:
1. **TT1 → TT7** — v0.1.0, first usable release. Review focus: event tap safety (keys must
   never get stuck), window activation correctness, permissions onboarding.
2. **TT8 → TT12** — v0.2.0, speed and customisation.
3. **TT13 → TT16** — v0.3.0, reach and accessibility.

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

## Deferred follow-ups
- Grid ↓ from a column that has no cell in a partial last row wraps to the top instead of
  the last item (tested as current behaviour; revisit with TT14 layout work).
- `GridLayout` shrinks to fit height only; very large card sizes on tiny screens can
  overflow horizontally.
- `.activeApp` scope with a frontmost app that has no windows shows an empty panel; show
  the app's windowless entry instead.
- Search highlights only the higher-scoring field when a token matches both.

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
