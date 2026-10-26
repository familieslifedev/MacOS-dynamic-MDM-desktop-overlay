# v0.6 — Validation and reliability

## Changes

- Added configuration validation for mode, coordinates, transitions, simulated time and wallpaper frame completeness.
- Added non-destructive repair actions and exportable diagnostics that omit coordinates and absolute paths.
- Reduced periodic overlay polling to once per minute while retaining filesystem change detection.
- Added explicit wallpaper refresh after macOS wakes from sleep.
