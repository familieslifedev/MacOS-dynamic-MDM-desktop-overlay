# Dynamic Desktop Manager v0.6 — QA build

This build is based on the three supplied v0.5 files. It has **not** been compiled on macOS in this environment.

## Changes
- Manager validates configuration mode, solar coordinate ranges (without displaying values), fade, simulated clock and numbered frame completeness.
- Safe repair shortcuts: setup wizard and clear simulated clock. No destructive automatic repairs.
- Export redacted diagnostics via Save panel; does not include raw config, coordinates, absolute paths or event log.
- Overlay normal polling is now 60 seconds (previously 5 seconds); filesystem watchers still handle changes.
- Overlay explicitly refreshes on macOS wake.
- Existing v0.5 UI, startup controls and wizard retained.

## Install
Replace the three named files in your repository, preserving your ignored wallpaper images and wallpaper-config.json. Run `bash build-manager.sh`, quit the previous manager and `open DynamicDesktopManager.app`. In the manager use **Build & Restart** to compile the updated overlay too.

## QA
1. Check System tab validation and redacted export; confirm no coordinates or paths appear.
2. Test the setup wizard's Cancel and Finish.
3. Test invalid frame detection by temporarily renaming a frame, then restoring it.
4. Test live/simulated solar changes and 60-second frame refresh.
5. Test deliberate Stop, crash recovery, sleep/wake and external monitors.
6. Check compiler warnings and report them before committing.

## Caveats
- Still repository-based, not a signed/notarised standalone installer.
- Runtime tests and macOS compilation must be performed on your Mac.
- Export includes wallpaper collection names, which may be identifying if you chose a personal name.
- The overlay's existing recovery algorithm remains unchanged; extended crash-loop testing is still required.
