# Dynamic Desktop Manager

**v0.9.1 (pre-release)**

A native macOS menu bar manager and desktop-level wallpaper overlay supporting static images and locally calculated, solar-position-based dynamic wallpapers.

This fork extends [MacOS-MDM-desktop-overlay](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay). The overlay displays a click-through desktop-level window; **it does not change the system wallpaper setting, remove MDM, or modify device-management configuration**. Follow your organisation's policies.

## Features

- SwiftUI menu bar manager with **Wallpaper**, **Testing**, and **System** sections
- Static wallpapers and solar-position-based frame selection
- Local wallpaper collection import, selection, and manual frame gallery
- Simulated solar time presets and custom dates for testing
- Configurable crossfades (0–10 seconds)
- Desktop overlay windows on multiple displays
- Four-step first-run setup assistant
- Overlay build, restart, stop, diagnostics, validation, and recovery controls
- Local solar calculations without network or Location Services access

## Requirements

- macOS Sonoma 14 or later as the intended baseline; full compatibility testing is pending
- Xcode Command Line Tools (`swiftc` and `xcrun`)
- User-supplied wallpaper images; no wallpaper collections are bundled

## Build and launch

From the repository root on macOS:

```sh
bash build-manager.sh
open DynamicDesktopManager.app
```

The build script compiles `DynamicDesktopManager.swift`. The manager's **Build** or **Build & Restart** controls separately compile `DesktopOverlay.swift` into `DesktopOverlayDynamic`. To build the overlay manually:

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
./DesktopOverlayDynamic
```

Do not run two overlay instances simultaneously; the overlay uses a single-instance lock. The manager currently expects its app bundle in the repository root, alongside the overlay executable, configuration, and assets. It is **not** a relocatable, signed, or notarised installer.

## First-run setup

Open the manager from the menu bar. Its setup assistant guides you through selecting or importing a collection, choosing static or solar mode, entering approximate coordinates for solar mode, and setting a crossfade duration. Imported wallpaper folders are copied locally; third-party images are not distributed with the repository.

The manager's **Wallpaper** tab lets you choose a collection, browse frames without changing the desktop image, and adjust crossfade duration. **Testing** provides simulated times and a return-to-live control. **System** contains login/startup preferences, validation, diagnostics, and recovery settings. Recovery works only while the manager remains open.

## Local configuration

The setup assistant can write `wallpaper-config.json`. For manual configuration, place it in the repository root (next to the compiled overlay):

```json
{
  "mode": "solar",
  "latitude": 0.0,
  "longitude": 0.0,
  "wallpaperSet": "The Desert",
  "crossfadeSeconds": 1.5
}
```

Replace the example coordinates with your own approximate values **locally**. They are decimal degrees. The optional `testDateTime` field is reserved for simulated solar time; remove it to return to live time. See [solar testing](SOLAR-TESTING.md).

For static mode, use `"mode": "static"` and place `wallpaper.jpg` or another supported `wallpaper.*` image next to the executable. For solar mode, use the original exported HEIC frame indices in filenames:

```text
Apple Dynamic Wallpapers/
├── The Desert/
│   ├── The Desert - 01.jpg
│   └── ... The Desert - 08.jpg
└── Solar Gradients/
    ├── Solar Gradients - 01.jpg
    └── ... Solar Gradients - 16.jpg
```

The Desert, The Cliffs, The Lake, and The Beach use eight frames; Solar Gradients uses sixteen. The selector approximates solar-position metadata and **does not reproduce Apple's proprietary interpolation or exact timing**.

## Privacy, limitations, and licensing

Solar calculations run locally. Do not commit `wallpaper-config.json`, downloaded/exported wallpaper images, credentials, or confidential device details. `.gitignore` excludes local configuration, assets, and built binaries.

All connected displays currently share the same selected wallpaper collection and frame. Login-item registration may require signing. Signing, notarisation, relocatable installation, and broader macOS validation remain future work.

The upstream repository has no explicit licence identified in the existing notices. The repository's MIT `LICENSE` applies **only to authorised original contributions**, not inherited upstream code or third-party assets. Resolve upstream redistribution rights before distributing full-source packages or binaries. See [NOTICE.md](NOTICE.md).

## Documentation

- [Solar engine and frame mappings](SOLAR-ENGINE.md)
- [Solar testing and regression checks](SOLAR-TESTING.md)
- [Release history](CHANGELOGS/README.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Third-party notices](NOTICE.md)
- [Original-contributions licence](LICENSE)

## Credits

Based on [iamrobertorodriguez/MacOS-MDM-desktop-overlay](https://github.com/iamrobertorodriguez/MacOS-MDM-desktop-overlay). This project is independent and is not endorsed by Apple or the upstream author.
