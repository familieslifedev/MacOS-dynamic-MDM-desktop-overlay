# v0.9.0 — Cleanup of dead code and documentation refresh

## Changes

- Removed the obsolete `DesktopOverlay-Solar-Metadata.swift` historical snapshot; retain the metadata-derived frame mappings in the active overlay.
- Removed unused sunrise/sunset helper functions from `DesktopOverlay.swift` without changing live frame selection.
- Retired the one-time `add_solar_test_mode.py` migration script now that simulated time is built into the overlay.
- Refreshed solar-engine documentation and testing instructions to reflect the manager's existing Testing interface.
- Added a changelog index and correct documentation links.
- Added manager app version metadata (`0.9.0`) to the build-generated `Info.plist`.
- Updated the diagnostics export version label to `0.9.0` or source it from the app bundle.
- Refreshed repository development instructions for the current manager/overlay architecture.

### v0.9.1

- Updated documentation grammar and naming

## Known limitations

- Solar frame selection approximates Apple's metadata-based timing and does not replicate Apple's interpolation.
- App bundle remains source-tree-relative and is not signed, notarised, or relocatable.
- Upstream redistribution permissions remain unresolved; see [NOTICE.md](../NOTICE.md).
