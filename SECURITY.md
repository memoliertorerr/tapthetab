# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report them privately through GitHub's private vulnerability reporting:
go to the repository's **Security** tab → **Report a vulnerability**
(<https://github.com/memoliertorerr/tapthetab/security/advisories/new>).

Please include:

- what the problem is and what an attacker could do with it,
- steps to reproduce (a proof of concept if you have one),
- the TapTheTab version (menu bar icon → About) and your macOS version.

You can expect an acknowledgement within a week. We will keep you updated while we
work on a fix, publish a GitHub Security Advisory together with the fixed release,
and credit you unless you prefer to stay anonymous.

## Supported versions

Only the **latest release** receives security fixes. Please check that the problem
still exists in the latest release (or on `main`) before reporting.

| Version        | Supported |
| -------------- | --------- |
| Latest release | Yes       |
| Older releases | No        |

## What TapTheTab can access

TapTheTab is a window switcher, so it needs more access than most apps. Each
permission is granted by you in **System Settings → Privacy & Security** and can be
revoked there at any time.

- **Accessibility** (required): to detect the switcher shortcut (⌥⇥) and the keys you
  press while the switcher is open, to list windows, and to focus, close, minimize,
  hide or full-screen the window you choose.
- **Screen Recording** (optional): only used to draw live window previews when you
  turn previews on. Without it, TapTheTab shows app icons and window titles instead.

TapTheTab is not sandboxed (the App Sandbox does not allow controlling other apps'
windows), but it is built with the hardened runtime and requests no extra
entitlements.

## Our privacy promise

- **No network access.** TapTheTab never makes network connections: no update
  checks, no crash reporting, no analytics.
- **No telemetry.** Nothing about you, your windows or your usage leaves your Mac.
- **Local configuration only.** Settings are stored in
  `~/Library/Application Support/TapTheTab/config.json`, readable and writable only
  by your user account (file permissions `0600`).

If you find TapTheTab doing anything that contradicts this, please treat it as a
security bug and report it as described above.
