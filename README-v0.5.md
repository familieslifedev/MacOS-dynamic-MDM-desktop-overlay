# Dynamic Desktop Manager v0.5 — First-Run Setup Assistant

This is a development/test build for the repository-based macOS manager. **Not compiled on macOS here.**

## Install

1. Back up the working v0.4 source and `wallpaper-config.json` locally.
2. Replace `DynamicDesktopManager.swift` and `build-manager.sh` in the repository with the included files.
3. Run `bash build-manager.sh` (or `chmod +x build-manager.sh && ./build-manager.sh`).
4. Quit the previous menu-bar manager and run `open DynamicDesktopManager.app`.
5. The wizard opens if the config is missing or invalid. Otherwise open **System → Run Setup Assistant Again**.

## Wizard

Welcome → Wallpaper collection → Solar configuration → Finish. The wizard preserves unknown JSON keys and existing coordinates when revisiting setup; coordinates are never logged. The `testDateTime` override is removed on Finish to restore live solar time. A configuration is not written until Finish. It saves atomically.

Wallpaper imports copy a source folder to `Apple Dynamic Wallpapers/`, require correctly named 8 frames (or 16 for Solar Gradients), and refuse to overwrite existing collections. **No Apple wallpapers are distributed.** For solar mode, decimal latitude and longitude are entered manually and validated. Static mode requires a separate `wallpaper.jpg` (or other supported wallpaper image) at the repository root; the collection picker is for solar mode.

## Important limitations

- This is **not** a standalone installer or packaged public release. It still expects the `.app`, overlay binary, config and image folders alongside the repository.
- The setup wizard does not obtain your location automatically or request macOS Location Services.
- It does not install wallpapers or build the overlay. Build it with the manager's Build action before selecting Start if necessary.
- The manager's auto-recovery and login registration remain subject to the limitations of v0.4.
- Test a clean setup with a backup; don't delete your private config to test without backing it up.

## QA checklist

1. With an existing valid config, wizard should not appear automatically. System → Run Setup Assistant Again should open it.
2. Cancel leaves the existing JSON unchanged.
3. Choose existing set, enter valid coordinates and Finish; JSON should retain unrelated keys and no testDateTime.
4. Try invalid coordinates; Finish should display validation error without changing JSON.
5. Import a properly named image folder; repeated import should fail safely.
6. Confirm wallpaper, testing and system controls still work, and Stop remains deliberate.
