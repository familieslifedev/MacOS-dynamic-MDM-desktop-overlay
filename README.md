# DesktopOverlay — Solar Dynamic fork additions

This folder is a **fork-ready set of changes** for [iamrobertorodriguez/MacOS-MDM-desktop-overlay](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay). It is **not a GitHub fork by itself**: to preserve the original project's commit history and fork relationship, use GitHub's **Fork** button first, then copy these files into your fork. Credit and link to the original author should be retained. Review the upstream repository's licence before redistributing.

## Features

- Original static `wallpaper.jpg` (or png/heic/etc.) mode if no `overlay.json` is present or `mode` is `static`.
- Solar-based eight-image selection using a configured latitude/longitude, without location services or network requests.
- Smooth configurable crossfade (default 1.5 seconds).
- Desktop-level, click-through overlay on each connected monitor; all monitors show the same image.
- Monitors for active image and directory changes, checks every 60 seconds, and keeps last good image if a file is missing or invalid.
- Background launch and single-instance lock retained.

## Create the fork on GitHub

1. Open the [upstream repository](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay) and click **Fork**. Name it however you like (for example, `MacOS-MDM-desktop-overlay-dynamic`).
2. Clone **your** fork locally: `git clone https://github.com/YOUR-USERNAME/MacOS-MDM-desktop-overlay.git`.
3. Copy the contents of this ZIP **into the cloned folder**, replacing its `DesktopOverlay.swift` and `README.md` (you may prefer to merge the README instead to retain the original usage instructions). Keep the upstream `.github/` directory and any other files intact.
4. Review with `git diff`, then `git add DesktopOverlay.swift README.md overlay.example.json .gitignore` and `git commit -m "Add solar dynamic wallpaper support and crossfades"`.
5. `git push origin main` (or your fork's branch name). Your repository will be marked as a fork of the original.

**Alternative:** In the original repo, create a new branch on your fork and commit these changes. Do not publish extracted Apple wallpaper images or work/private data without appropriate rights and permission.

## Build (macOS 14+)

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayLauncher
```

On your Mac, test from Terminal after stopping the original launcher; the original and dynamic editions use the same per-user lock. The source was prepared on Linux and **has not been compiled or runtime-tested on macOS**.

## Configuration

Copy `overlay.example.json` to `overlay.json`. Set `latitude` and `longitude` for the intended approximate location, `mode` to `solar`, and `wallpaperSet` to a directory name under `dynamic/`. Do not commit `overlay.json` if it contains location information.

```text
project/
  DesktopOverlay.swift
  overlay.example.json
  overlay.json                   # local-only config (ignored by Git)
  wallpaper.jpg                  # optional static fallback
  dynamic/
    The Desert/
      01.jpg
      02.jpg
      ...
      08.jpg
```

The app assumes files `01` to `08` are ordered dawn, morning, late morning, midday, afternoon, sunset, dusk, night. **Apple's HEIC order has not been verified**, so inspect/reorder the extracted stills. This is an approximate solar schedule, not Apple's original dynamic-wallpaper metadata engine. For static mode, set `mode` to `static` and use `wallpaper.jpg` next to the binary.

Run `./DesktopOverlayLauncher`. To inspect runtime messages:

```sh
log stream --style compact --predicate 'subsystem == "io.github.iamrobertorodriguez.DesktopOverlay"'
```

## Limitations and safety

- No per-monitor wallpaper selection.
- Fade behaviour and solar transitions require real-world testing on macOS.
- Does not modify device management profiles or system wallpaper preferences; it overlays the desktop visually. Use on a managed device only with employer approval.
- Do not remove remote-support or management agents from a company computer without IT authorisation. If ScreenConnect was removed without approval, inform IT so they can restore required support access.
