# v0.9.0 — Cleanup and documentation refresh (draft)

**Status: planned / in progress.** Check the final diff and regression results before marking this release complete.

## Planned changes

- Remove the obsolete `DesktopOverlay-Solar-Metadata.swift` historical snapshot; retain the metadata-derived frame mappings in the active overlay.
- Remove unused sunrise/sunset helper functions from `DesktopOverlay.swift` without changing live frame selection.
- Retire the one-time `add_solar_test_mode.py` migration script now that simulated time is built into the overlay.
- Refresh solar-engine documentation and testing instructions to reflect the manager's existing Testing interface.
- Add a changelog index and correct documentation links.
- Add manager app version metadata (`0.9.0`) to the build-generated `Info.plist`.
- Update the diagnostics export version label to `0.9.0` or source it from the app bundle.
- Refresh repository development instructions for the current manager/overlay architecture.

## Verification required before release

- Run the 2,400-case solar regression harness.
- Compile the manager and overlay on macOS.
- Test static/solar modes, gallery, simulated time, crossfades, multi-display behaviour, sleep/wake, and process controls.
- Review privacy exclusions and licensing notices.

## Known limitations

- Solar frame selection approximates Apple's metadata-based timing and does not replicate Apple's interpolation.
- App bundle remains source-tree-relative and is not signed, notarised, or relocatable.
- Upstream redistribution permissions remain unresolved; see [NOTICE.md](../NOTICE.md).
