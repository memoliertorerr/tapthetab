# TapTheTab — standing instructions

Instructions for anyone (human or automated) working in this repository. Read this file
and `docs/ROADMAP.md` before starting any change.

## What this is
TapTheTab is a keyboard-first window switcher for macOS 13+ (menu-bar agent app,
`LSUIElement`). ⌥⇥ shows every window, typing fuzzy-searches, releasing ⌥ switches.
MIT licensed. No telemetry, and no network access except the opt-in update check (off by
default; see `docs/ROADMAP.md` → Decisions) — that is a product promise, not a default.

## Layout
| Path | What | Builds on |
|---|---|---|
| `Sources/TapTheTabCore/` | Pure Swift + Foundation logic: session state machine, fuzzy matcher, recency, filters, key routing, shortcuts, config | macOS + Linux |
| `Tests/TapTheTabCoreTests/` | XCTest suite for the core | macOS + Linux |
| `Sources/TapTheTab/App/` | Entry point, app delegate, coordinator, menu bar, config controller, `Interfaces.swift` (contracts between layers) | macOS |
| `Sources/TapTheTab/System/` | Event tap, window catalog (CGWindowList + AX), focus tracking, window actions, thumbnails, permissions | macOS |
| `Sources/TapTheTab/UI/` | Switcher panel (NSPanel + SwiftUI), settings, onboarding | macOS |
| `scripts/`, `Resources/`, `Makefile` | App bundle assembly, icon, packaging, notarization | macOS |
| `.github/workflows/` | CI (Linux core + macOS build) and tag-driven releases | — |
| `docs/` | Roadmap/plan, architecture | — |

## Commands
- Core tests anywhere: `swift test`
- macOS: `make test`, `make app` (→ `dist/TapTheTab.app`), `make run`, `make package`
- Verify before every commit: `swift build && swift test` must be green. On macOS also `make app`.

## Rules
1. **Logic goes in the core.** Anything that can be expressed on plain values (ordering,
   filtering, matching, key handling, layout math, config) lives in `TapTheTabCore` with
   tests. The macOS layer only translates between the OS and core values.
2. **No network, no telemetry, no third-party runtime dependencies.** The only network
   access is the update check (`System/Updater.swift`): opt-in (`behavior.checkForUpdates`,
   default off) or started by the user from the menu, talking only to GitHub, sending nothing
   but the request. Don't add other network access or a package dependency without a
   written decision in `docs/ROADMAP.md`.
3. **Never log window titles or app content publicly**: use `privacy: .private` in `Log.*`.
4. **Config compatibility:** every config key is optional when decoding and a bad value
   falls back to its default. Never rename or remove a key without migration code and a
   CHANGELOG entry.
5. **macOS 13 deployment target.** APIs newer than 13 must be behind `#available`.
6. **Swift 5 language mode.** Main-actor UI types are `@MainActor`; callbacks from C APIs
   (event taps, AX observers) hop with `DispatchQueue.main.async` rather than unchecked casts.
7. **Private APIs** are allowed only where no public API exists. Resolve them at runtime
   in `System/PrivateAPI.swift` (`dlsym`, never `@_silgen_name`, which would stop the app
   from launching if Apple removed the symbol), handle a missing symbol by disabling only
   that feature, and list them in `docs/ARCHITECTURE.md`. Current list:
   `_AXUIElementGetWindow`, `CGSSetSymbolicHotKeyEnabled`, `CGSMainConnectionID`,
   `CGSCopyManagedDisplaySpaces`, `CGSCopyWindowsWithOptionsAndTags`, `GetProcessForPID`
   (public but deprecated), `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`.
8. **Never weaken a test to get green.** Change a test only when the behaviour change is
   intended, and say so in the commit message.
9. **Commits:** Conventional Commit style (`feat:`, `fix:`, `docs:`, `ci:`, `test:`,
   `refactor:`, `chore:`), imperative, no tool or assistant names in messages. Author is the
   repository owner's configured identity.
10. **Branches:** work on short-lived branches (`feat/…`, `fix/…`, `docs/…`), merge to
    `main` through a pull request once CI is green. Never force-push `main`.
11. **Secrets:** never commit certificates, keys, `.env` files or tokens. Signing material
    exists only as GitHub Actions secrets (see `scripts/notarize.sh` and
    `.github/workflows/release.yml`).
12. **Releases:** bump `VERSION`, move `CHANGELOG.md` `[Unreleased]` items under the new
    version, merge, then tag `vX.Y.Z` on `main` (or run the Release workflow with the version).
13. Keep `README.md`, `CHANGELOG.md`, `docs/ROADMAP.md` and this file current in the same
    change that makes them stale.
