# Copilot instructions — Dynamic Desktop Manager

## Project architecture

This repository contains **two active Swift source files**, compiled directly with `swiftc` (no Xcode project or Swift package):

- `DynamicDesktopManager.swift`: SwiftUI menu bar manager, setup assistant, wallpaper gallery, simulated solar time controls, diagnostics, and overlay process controls.
- `DesktopOverlay.swift`: AppKit desktop-level overlay, static/solar image selection, crossfades, display management, file watching, and wake refresh.

`DesktopOverlay-Solar-Metadata.swift` is an obsolete historical snapshot, not a build input; it is slated for removal in v0.9. Do not revive its older asset-path logic.

## Build and test

Run from the repository root on macOS:

```sh
bash build-manager.sh
open DynamicDesktopManager.app
python3 run_solar_unit_tests.py
```

The manager's **Build** or **Build & Restart** controls compile `DesktopOverlay.swift` with AppKit and QuartzCore into `DesktopOverlayDynamic.next`, then replace `DesktopOverlayDynamic` on success. For a manual overlay build:

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
```

The manager app and overlay executable currently live alongside repository assets and configuration. Do not assume the app bundle is relocatable. Keep built executables and local data ignored by Git.

## Assets and configuration

- `wallpaper-config.json` lives next to the overlay executable and is local-only.
- Static mode uses a supported `wallpaper.*` image beside the executable.
- Solar collections use `Apple Dynamic Wallpapers/<set>/<set> - NN.jpg` (or a supported alternative image extension).
- Landscape collections use eight frames; Solar Gradients uses sixteen.
- Preserve original HEIC export frame numbers. They are **not** necessarily chronological.
- Optional `testDateTime` is a UTC ISO 8601 override; remove it to restore live solar time.
- Never commit private coordinates, proprietary wallpaper assets, credentials, or confidential MDM details.

## Engineering conventions

- Preserve executable-relative paths and the manager's repository-root assumptions unless deliberately redesigning installation.
- Preserve one click-through desktop-level overlay window per display, main-thread AppKit updates, and display/sleep/wake refresh behaviour.
- Preserve the solar anchor mappings, `Solar.position()`, and `Solar.frame()`; do not silently change frame timing.
- Keep crossfades, file watchers, and the single-instance lock working.
- The gallery is preview-only and must not intercept adjacent controls or alter the desktop wallpaper.
- Keep recovery semantics accurate: recovery works while the manager is running, and explicit Stop must prevent automatic relaunch.
- Keep source changes focused and run solar tests and macOS manual regression checks after modifying the overlay.
- Update `README.md`, `SOLAR-ENGINE.md`, `SOLAR-TESTING.md`, and the appropriate version changelog when behaviour changes.

## Legal and distribution

This is a fork of an upstream repository with unresolved redistribution permissions. The local MIT licence covers authorised original contributions only. Do not package or redistribute upstream-derived binaries or Apple wallpaper assets without appropriate rights; see `NOTICE.md`.
