# MacOS Dynamic MDM Desktop Overlay

A macOS desktop-level wallpaper overlay with **static** and **solar dynamic** modes. This fork extends [iamrobertorodriguez/MacOS-MDM-desktop-overlay](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay) with solar-position-based image selection and configurable crossfades.

The overlay draws over the desktop wallpaper; it **does not change macOS wallpaper preferences, remove device management, or modify MDM settings**.

## Features

- Static wallpaper fallback (`wallpaper.jpg`, `.png`, `.heic`, and other supported formats).
- Solar wallpaper selection from locally extracted Apple dynamic wallpaper frames, using configured latitude and longitude.
- Approximate metadata-derived mappings for **The Desert**, **The Cliffs**, **The Lake**, **The Beach** (eight frames each), and **Solar Gradients** (16 frames).
- Configurable crossfade (default 1.5 seconds), click-through overlays on connected displays, and refresh/file monitoring.
- Local calculations; no location-service permission or network lookup is required.

## Requirements and build

Build on macOS with the Swift compiler and AppKit/QuartzCore frameworks:

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
```

The built executable uses the **directory containing the executable** as its base directory. Keep it in the repository root alongside `wallpaper-config.json` and the wallpaper folders, or adjust your deployment accordingly.

The original overlay and this fork use the same per-user single-instance lock. **Quit the original process before launching this build**:

```sh
./DesktopOverlayDynamic
```

The application may relaunch itself in the background. If it seems to exit immediately, check for another running overlay before assuming it failed.

## Local configuration

Create a file named **`wallpaper-config.json`** beside `DesktopOverlayDynamic`:

```json
{
  "mode": "solar",
  "latitude": 0.0,
  "longitude": 0.0,
  "wallpaperSet": "The Desert",
  "crossfadeSeconds": 1.5
}
```

Replace the example coordinates **locally** with your approximate latitude and longitude. They must be JSON numbers, not quoted strings. `wallpaperSet` is the name of a single folder under `Apple Dynamic Wallpapers/`. Change it to `The Cliffs`, `The Lake`, `The Beach`, or `Solar Gradients` to select another set.

**Never commit your actual `wallpaper-config.json`.** The `.gitignore` should exclude it, along with `Apple Dynamic Wallpapers/` and the compiled `DesktopOverlayDynamic` binary. Verify the ignore rules before pushing changes.

For static mode, set `"mode": "static"` and put `wallpaper.jpg` (or another supported `wallpaper.*` extension) beside the executable. If the config is absent, the application defaults to static mode.

## Wallpaper folder layout

```text
MacOS-dynamic-MDM-desktop-overlay/
├── DesktopOverlay.swift
├── DesktopOverlayDynamic               # local build; ignored by Git
├── wallpaper-config.json               # private; ignored by Git
├── README.md
├── Solar-Metadata-Update-README.md
└── Apple Dynamic Wallpapers/           # local assets; ignored by Git
    ├── The Desert/
    │   ├── The Desert - 01.jpg
    │   ├── The Desert - 02.jpg
    │   └── ... The Desert - 08.jpg
    ├── The Cliffs/
    │   └── The Cliffs - 01.jpg ... 08.jpg
    ├── The Lake/
    │   └── The Lake - 01.jpg ... 08.jpg
    ├── The Beach/
    │   └── The Beach - 01.jpg ... 08.jpg
    └── Solar Gradients/
        └── Solar Gradients - 01.jpg ... 16.jpg
```

The app constructs filenames from the selected **folder name**, followed by ` - ` and a **two-digit frame number**, then checks supported image extensions. Keep the extracted frame numbers aligned with their original HEIC image indices; **do not rename frames into chronological order**. Apple wallpaper assets are not distributed with this repository.

## How solar selection works

The application calculates the sun's approximate altitude and azimuth from the current time and the coordinates in the private configuration. It chooses the nearest mapped altitude anchor, distinguishing morning from evening using solar azimuth. The landscape sets and Solar Gradients use different mappings; see [Solar-Metadata-Update-README.md](Solar-Metadata-Update-README.md).

The result is **an approximation of Apple's dynamic wallpaper selection**, not a reproduction of Apple's proprietary interpolation or transition timings. Frame changes are checked about once per minute. Smooth fades and longer-running transitions still warrant real-world testing.

## Diagnostics and limitations

To view application logs:

```sh
log stream --style compact --predicate 'subsystem == "io.github.iamrobertorodriguez.DesktopOverlay"'
```

- All connected displays use the same selected image; per-monitor selection is not implemented.
- The app preserves the last successfully loaded wallpaper if a required frame is temporarily unavailable.
- The solar model is approximate and assumes the configured coordinates match the Mac's intended location.
- No Apple wallpaper images, personal coordinates, or built executables should be included in public commits.

## Attribution

Based on the original [MacOS-MDM-desktop-overlay](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay). Preserve upstream attribution and check the upstream licence and the rights associated with any wallpaper assets before redistribution.
