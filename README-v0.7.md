# Dynamic Desktop Manager v0.7 — Interface polish / QA

Built from the v0.6 source ZIP, preserving the v0.6 overlay, validation, diagnostics, recovery and first-run setup wizard.

## New
- Larger, framed wallpaper gallery in the Wallpaper tab.
- Previous/Next buttons browse each collection's 8 frames (16 for Solar Gradients), without changing the actual desktop or config.
- Missing frame fallback instead of a blank preview.
- Clearer running/stopped indicator in the header.
- Refresh status also refreshes installation validation.
- Gallery resets to frame 1 when changing wallpaper collections.

## Installation
Extract the ZIP and replace the named Swift and shell files in the repository. Keep `wallpaper-config.json` and the ignored Apple wallpaper images intact. Quit the running manager, then:

```bash
bash build-manager.sh
open DynamicDesktopManager.app
```

The overlay source is included unchanged from v0.6; no overlay rebuild is necessary if v0.6 was already installed.

## QA
- Browse frames 1–8 (or 1–16 for Solar Gradients), including wrapping at either end.
- Switch collections and check preview resets to frame 1.
- Temporarily hide one image to check the missing-frame placeholder; restore it afterwards.
- Verify gallery navigation does not change the actual desktop.
- Verify first-run wizard, diagnostics, testing, Build/Restart/Stop and login controls still work.

**Build status:** macOS compilation and runtime testing are required on your Mac. The development ZIP is not signed or notarized. No copyrighted wallpaper images or private config are included.
