# Solar wallpaper testing

## Installation

From the repository root, back up your working source, then run the patch:

```bash
cp DesktopOverlay.swift DesktopOverlay.before-test-mode.swift
python3 ~/Downloads/add_solar_test_mode.py
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
```

Keep the backup local; do not commit it accidentally. `add_solar_test_mode.py` preserves the current `Apple Dynamic Wallpapers/<set>/<set> - NN.jpg` naming and other existing changes.

## Simulated clock

Add an optional UTC ISO 8601 timestamp to your **local** `wallpaper-config.json`:

```json
"testDateTime": "2026-06-21T06:00:00Z"
```

This is **one additional property**, not a standalone JSON file. Keep your existing mode, coordinates, wallpaperSet, and crossfadeSeconds fields. Use a valid UTC timestamp with `Z`; for a local clock time, convert to UTC first. The app's existing refresh timer polls approximately once per minute; restart the app if you want to see a change immediately. **Stop the existing overlay process normally before starting the newly compiled one** (they share a single-instance lock). The selected frame depends on date, season and location, not just the hour.

Suggested test timestamps (all UTC):

- `2026-06-21T00:00:00Z`
- `2026-06-21T04:00:00Z`
- `2026-06-21T08:00:00Z`
- `2026-06-21T12:00:00Z`
- `2026-06-21T16:00:00Z`
- `2026-06-21T20:00:00Z`

Record which JPEG appears, verify it fits the approximate solar lighting, and check for black flashes during transitions. To test a fade, change the timestamp to one selecting a different frame, save the config, and wait for the next refresh. The timer and directory watcher may introduce a short delay.

**Remove `testDateTime` to restore live solar time.** Do not commit `wallpaper-config.json`; it contains private coordinates.

## Automated solar checks

```bash
python3 ~/Downloads/run_solar_unit_tests.py
```

This extracts the **actual** `Solar` implementation from your current Swift source and compiles a temporary Swift test harness. It checks frame bounds, deterministic output, and finite solar positions across 2,400 combinations (5 sets × 4 locations × 5 months × 24 hours). It does **not** prove Apple's exact frame mapping or the GUI crossfade.

## Manual regression checks

- Launch with `testDateTime` absent and verify live solar mode.
- Change `wallpaperSet` and verify the corresponding named images load.
- Change `testDateTime` across sunrise/sunset and watch for a smooth crossfade.
- Check all attached displays; unplug/replug a display.
- Confirm sleep/wake selects the current frame on the next refresh.
- Confirm static `wallpaper.jpg` mode still works.
- Temporarily move a JPEG and confirm the app retains the last good image; restore it afterward.
- Use malformed testDateTime and confirm an error is logged without crashing.

## Safety and version control

Keep `wallpaper-config.json`, `Apple Dynamic Wallpapers/`, and the executable ignored by Git. Do not run the original overlay simultaneously with the test build. These scripts are intended for development, not an unattended production install.
