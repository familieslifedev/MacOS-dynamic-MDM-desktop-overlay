# Dynamic Desktop Manager

A native macOS menu bar interface and desktop-level wallpaper overlay supporting static wallpapers and locally calculated, solar-position-based dynamic wallpapers.

This project extends [MacOS-MDM-desktop-overlay](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay). The overlay draws a click-through window at desktop level. **It does not modify the system wallpaper preference, remove MDM, or change device management settings.** Follow your organisation's device policies.

## Features

- Native SwiftUI menu bar controls for the desktop overlay
- Static image support and solar-driven wallpaper frame selection
- Local wallpaper collection selection and manual frame gallery
- Solar time simulation for previewing time-dependent behaviour
- Configurable image crossfades
- Multi-display desktop overlays
- First-run configuration assistant
- Startup preferences, process controls, diagnostics, validation and recovery options
- Local-only solar calculations; no network or Location Services permission needed

## Requirements

- macOS Sonoma 14 or later (upstream baseline); newer SwiftUI and ServiceManagement functionality may have additional requirements
- Xcode Command Line Tools with `swiftc` and `xcrun`
- Wallpaper image files supplied by the user (not bundled)

## Build and launch

Clone the repository and run from its root:

```sh
bash build-manager.sh
open DynamicDesktopManager.app
```

The manager currently expects its `.app` bundle to remain **inside the repository root**, alongside the source, configuration and overlay executable. This is a source-build distribution, **not yet a relocatable or signed/notarised application**.

The manager offers controls to build or restart the overlay. Alternatively, compile the overlay directly:

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
./DesktopOverlayDynamic
```

## Configuration

The first-run assistant can create the local configuration. For manual setup, place `wallpaper-config.json` in the repository root:

```json
{
  "mode": "solar",
  "latitude": 0.0,
  "longitude": 0.0,
  "wallpaperSet": "The Desert",
  "crossfadeSeconds": 1.5
}
```

Replace the sample coordinates locally. Latitude and longitude are decimal degrees. For static mode use `"mode": "static"` and place a `wallpaper.jpg` (or supported alternative) in the repository root. Solar mode expects numbered image frames in `Apple Dynamic Wallpapers/<collection>/` with filenames such as `The Desert - 01.jpg`. Landscape sets expect eight frames; Solar Gradients expects sixteen.

The dynamic frame choice approximates solar-position metadata; it does not replicate Apple's proprietary wallpaper interpolation.

## Privacy and assets

The program calculates solar position locally. Coordinates are stored in a local JSON file. Do not commit local coordinates or wallpaper assets. Proprietary Apple wallpaper images are **not** included and must not be redistributed without appropriate rights.

## Limitations

- All displays currently use the same wallpaper collection and selected image.
- This project uses desktop-level overlay windows rather than modifying system wallpaper settings.
- Signing, notarisation, relocatable installation and broad macOS compatibility verification are future release tasks.
- Login item registration may require an appropriately signed application.

## Documentation

- [Release history](CHANGELOGS/README.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Third-party notices and licensing](NOTICE.md)
- [Original-contributions licence](LICENSE)

## Credits and licensing

Based on the upstream [MacOS-MDM-desktop-overlay](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay). See [NOTICE.md](NOTICE.md) for an important licensing caveat: **the upstream repository does not currently display an explicit licence**. The included MIT licence covers only original contributions by this project's contributors, not upstream code or third-party wallpaper assets. Confirm upstream redistribution permission before publishing a packaged release.
