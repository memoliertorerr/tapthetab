# Research: windows from virtual machines and Windows apps (2026-10-28)

Question: does TapTheTab list apps running inside a VM as separate entries, or only the
VM window? Nothing below was tested on a Mac; "verified" means a public source says so.

| Product / mode | Separate entries? | Why |
|---|---|---|
| Parallels — Window / Full Screen | No, one VM window | The guest is drawn inside one standard macOS window. |
| **Parallels — Coherence** | **Yes (expected)** | Each Windows app runs as its own macOS process from a Parallels-made bundle (`com.parallels.winapp.*`) with its own Dock icon; its windows report `AXWindow` / `AXDialog` with titles (verified in yabai and Hammerspoon issues). Name and icon come from that process. |
| VMware Fusion — Unity | No | Unity was removed in Fusion 13.6 and never existed on Apple silicon. |
| UTM (QEMU / Apple Virtualization) | No, VM window only | No seamless mode; requested and declined upstream. |
| VirtualBox — seamless | No | One host window covering the desktop with the guest background masked out. |
| Apple Virtualization macOS guests (Tart, VirtualBuddy) | No | Whole-display view only. |
| **CrossOver / Wine / Whisky / GPTK** | **Yes, since 0.6.0** | Each .exe is its own macOS process. Windows that draw their own frame report subrole `AXUnknown`, which TapTheTab used to drop. |
| Windows App (RemoteApp), Citrix Workspace | Probably | Integrated/seamless apps are macOS windows; subroles unverified. |

## What changed (0.6.0)

`WindowAdmission` (core, tested) decides which Accessibility windows are switchable:
standard windows always; dialogs only with a title (untitled ones are pop-ups and
toasts); `AXUnknown` windows only when titled, on window-server layer 0, visible and at
least 100×50 — what self-drawn Wine/CrossOver windows look like, but not overlays.
Window-server z-order is now recorded for every layer, so windows kept above layer 0
still count as on screen. Copy Diagnostics lists how many windows were skipped by
subrole (Apple's names only), to explain what is still missing on a given Mac.

## Not done, on purpose

- Accepting `.accessory` apps in general: would bring in menu-bar palettes and HUDs.
- Mapping windows owned by one VM process to per-app proxy bundles by title: fragile.
- Better names for Wine processes that report as `wine64-preloader` (use the .exe name
  from the process arguments): possible later.

## Sources

Hammerspoon #1118; yabai #622; AltTab issues #1213, #6118, #1067, #671 and PRs #2589,
#2609 (GPL, approach only); Wine `dlls/winemac.drv`; Parallels KB 4670 and forums;
VMware Fusion 13.6 release notes; UTM #4095, #3554; VirtualBox manual (guest additions);
Microsoft Windows App feature comparison; Citrix Workspace app preferences.
