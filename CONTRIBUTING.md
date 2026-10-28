# Contributing to TapTheTab

Thanks for helping! Bug reports, ideas and pull requests are all welcome.
For security problems, please follow [SECURITY.md](SECURITY.md) instead of opening an issue.

## Prerequisites

- macOS 13 Ventura or later
- Xcode 16 (Swift 6 toolchain), or the matching Command Line Tools

The core library (`TapTheTabCore`) is plain Swift + Foundation and also builds and
tests on Linux with Swift 6.1, which is handy for quick logic changes.

## Build, test, run

```sh
make test       # swift test
make app        # builds dist/TapTheTab.app (ad-hoc signed)
make run        # opens dist/TapTheTab.app (builds it first if needed)
```

`make help` lists everything else (`build`, `universal`, `package`, `clean`, `lint`).
`make lint` runs SwiftFormat/SwiftLint only if you have them installed.

The first launch asks for the Accessibility permission. Locally built apps are
ad-hoc signed, so macOS may treat every rebuild as a new app: if the shortcut stops
working after a rebuild, remove TapTheTab from **System Settings → Privacy & Security
→ Accessibility** and add it again.

## Project layout

| Path                     | What lives there                                                                 |
| ------------------------ | -------------------------------------------------------------------------------- |
| `Sources/TapTheTabCore/` | Platform-independent logic: configuration, search, ordering, layout, key routing. No AppKit. |
| `Tests/TapTheTabCoreTests/` | Unit tests for the core. New logic should come with tests here.              |
| `Sources/TapTheTab/`     | The macOS app (AppKit/SwiftUI): permissions, window access, hotkeys, UI, menu bar. |
| `Resources/`             | `Info.plist` template and entitlements used by the build script.               |
| `scripts/`               | `build-app.sh`, `package.sh`, `notarize.sh`, icon generator, CI helpers.        |
| `.github/workflows/`     | CI (`ci.yml`) and releases (`release.yml`).                                    |

Prefer putting logic in `TapTheTabCore` where it can be tested without a Mac UI, and
keep the app layer thin.

## Branches and pull requests

1. Create a branch from `main` named after the change, e.g. `feat/window-pinning` or
   `fix/stale-previews`.
2. Use [Conventional Commit](https://www.conventionalcommits.org/) style messages:
   `feat: add window pinning`, `fix: ignore minimized windows in same-app mode`,
   `docs: …`, `test: …`, `refactor: …`, `ci: …`, `chore: …`.
3. Run `make test` (and `make app` for app changes) before pushing.
4. Open a pull request against `main` and fill in the template. CI must be green:
   it tests the core on Linux and builds, tests and packages the app on macOS.
5. Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for
   user-visible changes.

Please keep the privacy promise intact: no network access and no telemetry.

## Releases

Maintainers release like this:

1. Bump the version in `VERSION` (for example `0.2.0`) and move the `Unreleased`
   entries in `CHANGELOG.md` under a new `## [0.2.0] - YYYY-MM-DD` heading.
2. Merge that to `main`.
3. Push the tag: `git tag v0.2.0 && git push origin v0.2.0`, or run the
   **Release** workflow from the Actions tab with version `0.2.0` (it creates the tag).

The release workflow checks that the tag matches `VERSION`, runs the tests, builds a
universal app, packages a `.zip`, a `.dmg` and `SHA256SUMS.txt`, and publishes a
GitHub release with the changelog section as release notes. Versions with a
suffix such as `0.2.0-beta.1` are published as pre-releases. Builds are signed
with a Developer ID and notarized only when the signing secrets listed at the top
of `.github/workflows/release.yml` are configured; otherwise they are ad-hoc
signed and the release notes explain how to open them.
