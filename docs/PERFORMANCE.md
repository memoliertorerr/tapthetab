# Soak and local performance evidence

TapTheTab has a deterministic soak of its switching and preview-capture policies. It runs in
two places:

- **`swift test`** (every CI run): `Tests/TapTheTabSoakTests/SwitchingSoakTests.swift` runs
  small fixed-seed workloads. It asserts behaviour only, never wall-clock time, so results
  do not depend on the machine.
- **`make soak`** (opt-in, local): the `TapTheTabSoak` command runs larger workloads and also
  reports what this process measured while running them.

Both use fictional windows on a virtual clock. They open no windows, ask for no permissions,
read or change no settings, install no event tap and use no network. **Passing shows that the
core policies keep their contracts under the simulated load. It does not show how AppKit,
Accessibility or ScreenCaptureKit perform on a real Mac.** Those checks remain with the
maintainer (see `docs/ROADMAP.md`, TT56–TT58).

## Running it

```sh
make soak                                          # default: 400 sessions, seed 0x7ab55eed
make soak SOAK_ARGS="--iterations 20000 --windows 800 --steps 400 --seed 0xC0FFEE"
swift run -c release TapTheTabSoak --iterations 5000 --seed 7
swift run -c release TapTheTabSoak --help
```

| Option | Meaning | Range | Default |
|---|---|---|---|
| `--iterations N` | Switcher sessions to open and close | 1–1,000,000 | 400 |
| `--seed S` | Workload seed, decimal or `0x` hex | any 64-bit unsigned | `0x7ab55eed` |
| `--windows N` | Largest synthetic window catalog | 2–5,000 | 120 |
| `--steps N` | Most inputs in one session | 1–10,000 | 120 |

`iterations × steps` may be at most 50,000,000. This limits requested inputs, not run time:
catalog size and scenario mix also affect work. Freed window IDs are sampled in a pool
capped at 65,536 entries, so long runs do not grow that pool indefinitely.
Numbers must be plain ASCII digits. Unknown,
repeated, missing or out-of-range arguments are rejected with exit status 64. The command
runs on any platform where the core builds; its support target depends only on `TapTheTabCore`. The app does not link the simulation target.

- **Exit status:** 0 when every check held, 1 when a check failed (the first 20 violations are
  printed), 130 when stopped early.
- **Stopping:** Ctrl-C (or SIGTERM) stops after the current session. Late simulated answers
  are still drained and checked, then a partial report is printed.
- **Reproducing:** the report prints the seed and a digest of the run's event trace. Completed runs with the same
  seed and options give the same report and digest. A stopped partial run also depends on
  its stopping point. This was checked across
  separate runs on one Mac; Linux should match but has not been checked. The digest is not a
  stored reference value: it changes whenever the workload or a policy changes.

## What runs

`Sources/TapTheTabSoakSupport/SoakSimulation.swift` drives these **production** types directly:
`SwitcherSession` (navigation, search, actions, `replaceItems`), `ItemFilter`,
`LargePreviewCaptureSchedule`, `PreviewCaptureTarget`, `CaptureWorkLimiter` (screenshots and
window lists), `PreviewImageRetention`, `PreviewFreshness` and `FuzzyMatcher` (through
search).

The code that calls them follows the app's `SwitcherCoordinator`, `ThumbnailService` and
`LargePreviewStore`, but it is a **model of that code, not the app's code**. The macOS-only
values it needs are restated in `SoakAppLimits`: 4 screenshot calls running, 4 abandoned,
3 s timeouts, a window list reused for 1.5 s, 3 retained images and 16 megapixels. If the app's
values or call order change, update the model in the same change.

Sessions cycle through eight scenarios in order, so every scenario runs once a workload has
at least eight sessions:

| Scenario | Exercises |
|---|---|
| `rapidCycling` | Bursts of 1–5 steps 15–70 ms apart, then a pause or a 1.2–3 s rest |
| `slowBrowsing` | Steps 150–900 ms apart |
| `search` | Typing, deleting and clearing a fuzzy search |
| `catalogChurn` | Windows closing, opening, minimizing, apps hiding or quitting, window numbers reused by other apps, mid-session catalog refreshes |
| `lateCompletions` | Screenshot calls answering near or after their 3 s timeout, out of order |
| `hungCaptures` | Screenshot and window-list calls answering only after 3.5–20 s, saturating the limits; the effect carries into later sessions |
| `restingRefresh` | 1.5–20 s rests with frequent failures, so refreshes and back-off run |
| `quickTaps` | Sessions of 1–3 inputs, sometimes closed before the panel shows |

Catalogs are regenerated or changed between sessions, with up to `--windows` windows. They
include minimized windows, hidden apps, windowless apps, windows on other desktops and
displays, and the switcher's own window. Filters and scope are chosen at random for each
session. Every simulated call eventually answers, so the run always ends.

## What is checked

Each check describes behaviour the app depends on. None restates a policy's internal
branches:

- **Bounded native work:** at most 4 screenshot calls run at once, and at most 7 are
  outstanding, counting abandoned ones. No more than 7 start between two answers, however
  long the service hangs. At most one window-list fetch is outstanding. An answer the limiter
  does not recognise is a failure.
- **Screenshot watchdog deadline:** a call still marked running more than 3 s plus the
  10 ms watchdog floor and 5 ms tolerance is a violation, even after its session closes.
- **Drained at the end:** every abandoned call is released by its late answer. Neither limit
  stays blocked, nothing is still marked running, and no session is left open.
- **Settling while cycling:** after a selection change that counts as cycling (less than
  120 ms after the previous one), no capture starts within the 80 ms settle delay.
- **Final selection attempted:** a capture attempt follows each selection change within
  settle delay + capture timeout (1.08 s, plus 5 ms of tolerance). This check catches the
  regression where a completion replaced the settle timer with the 2 s refresh.
- **One capture at a time:** a large-preview capture starts only after the previous one
  finished or reached the schedule's 1 s timeout.
- **No frozen preview:** after a finished capture of a selected window, the next attempt
  comes within the 16 s back-off maximum.
- **Bounded retained images:** at most 3 large-preview images are kept. Over the 16-megapixel
  budget, only the image just stored and the protected selection remain. This holds across
  every session, because the app's store outlives a session.
- **Session state:** no item is listed twice, every listed item is in the session, the
  selection is in range and exists whenever the list is not empty, an empty query lists every
  item in order, and an activated item is listed.
- **Filtering:** order is kept. The switcher's own window and excluded apps (compared
  case-insensitively) are never listed, and neither are minimized windows when the filter
  hides them.
- **Bounded run:** an event-count ceiling turns a runaway timer loop into a failure.

The CI tests also check that the stressful paths actually run in the fixed workload: cycling,
deferred captures, refreshes, failures, skipped selections, timeouts, late answers, saturation,
window-list timeouts and refusals, superseded and out-of-order completions, results arriving
after their session closed, retention drops, catalog changes and window actions.

### Proof the checks catch regressions

`SwitchingSoakTests` runs the soak with four deliberately broken policies. Each must fail:

| Broken variant | Check that catches it |
|---|---|
| A completion during cycling schedules the 2 s refresh (the settle-timer regression) | Final selection attempted |
| Selection changes capture immediately, ignoring the settle delay | Settling while cycling |
| A limiter frees timed-out slots without counting them as abandoned | Bounded native work |
| Retention never drops an image | Bounded retained images |
| Screenshot watchdog never expires a call | Screenshot watchdog deadline |

On seeds 1–10 (96 sessions each), the settle-timer variant failed 1–7 times per seed, and
the production policies never failed. Two seeded property tests also run the production
policies directly. With nothing ever answering, `CaptureWorkLimiter` starts at most 7 calls
in an hour of retries, and late answers in random order each release one call exactly once.
`PreviewImageRetention` stays bounded and consistent over 20,000 random operations.

## Measurements

The command reports wall-clock time and CPU user/system time (`getrusage`) for the run. It
also reports the process's peak resident set (`ru_maxrss`) and, on macOS only, its physical
footprint before and after (`task_info`, `TASK_VM_INFO`). On Linux the footprint line says it
was not measured. Everything comes from public system calls; nothing was added as a
dependency.

These numbers describe this simulation process only: how fast the core policies handle a
synthetic load, and that the process stays small. They do not measure the app's memory
(real images are never created; retained "images" are pixel counts) or the cost of real
screenshots, window lists or Accessibility calls. Wall-clock numbers vary between machines
and runs, so no test uses them as a threshold.

### Recorded local runs

2026-11-08, Apple M1, release build, after capping the freed-ID pool. Local simulation
process evidence only; earlier uncapped-pool measurements were removed.

| Workload | Sessions / inputs | Simulated events | Wall clock | Peak RSS | Result |
|---|---|---|---|---|---|
| Default (seed `0x7ab55eed`) | 400 / 17,804 | 44,157 | 0.315 s | 7.8 MB | pass; digest `0xa32edf975fbbd672` |
| `--iterations 20000 --windows 5000 --steps 10 --seed 1` | 20,000 / 121,335 | 650,793 | 31.911 s | 14.2 MB | pass; digest `0x81ea0b7c724a4643` |

## Findings

- **No production bug was found.** The recorded completed workloads pass with the production policies.
- An early version of the 20,000-session run reported a frozen preview. The trace showed a
  modelling error: a capture finished after closing an app's windows had emptied the list.
  With nothing selected there is nothing to refresh. The check now applies only while a window
  is selected; the next selection is checked as a selection change.
- At first, the settle-timer variant went undetected, because rapid-cycling sessions never
  rested after a burst. The workload now has short bursts followed by rests.

- Independent review found that the freed-window-ID pool grew indefinitely; it is now
  capped at 65,536 entries and covered by a regression test. Deadline assertions and
  specific mutation-test messages were strengthened in the same review.

## Not covered

- Real AppKit, SwiftUI, Accessibility, ScreenCaptureKit, window-server and event-tap
  behaviour and timing, main-thread contention, real image memory and GPU work.
- Peek, the show-delay setting, the thumbnail cache, catalog refresh latency, `ItemOrdering`
  (grouping, pinning, display-first), `SpaceCoverage`, search memory and per-shortcut desktop
  coverage.
- Interactive stress on a real desktop, deliberately: it would move real windows and needs
  the maintainer's agreement.
