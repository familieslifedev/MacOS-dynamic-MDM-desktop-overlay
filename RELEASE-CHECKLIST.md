# v0.9.0 release readiness checklist

This checklist tracks **proposed** v0.9.0 cleanup and verification. Leave boxes unchecked until the work has actually been completed and tested.

## Source and build

- [ ] Remove the obsolete `DesktopOverlay-Solar-Metadata.swift` snapshot after confirming no build dependencies.
- [ ] Remove unused `Solar.elevation()` and `Solar.sunEvents()` from `DesktopOverlay.swift` without changing `Solar.position()`, `Solar.frame()`, or anchor mappings.
- [ ] Remove the obsolete `add_solar_test_mode.py` patch script.
- [ ] Update the manager's hardcoded diagnostics version from `v0.6` to `v0.9.0` (or read the app bundle version).
- [ ] Add `CFBundleShortVersionString=0.9.0` and an appropriate `CFBundleVersion` to the manager's generated `Info.plist` in `build-manager.sh`.
- [ ] Compile the manager with `bash build-manager.sh` on macOS.
- [ ] Build the overlay using the manager's Build or Build & Restart controls.
- [ ] Run `python3 run_solar_unit_tests.py` successfully.

## Manual regression

- [ ] Test first-run setup and local collection import.
- [ ] Test Wallpaper, Testing, and System navigation.
- [ ] Test collection selection and gallery hit testing.
- [ ] Test static and solar modes, crossfade, and simulated time.
- [ ] Test multi-display connect/disconnect and sleep/wake refresh.
- [ ] Test overlay start, stop, restart, diagnostics, validation, and recovery.
- [ ] Test from a clean source checkout on the intended macOS version(s).

## Documentation and repository safety

- [ ] Replace historical solar notes with `SOLAR-ENGINE.md` and update links.
- [ ] Update `README.md`, `SOLAR-TESTING.md`, and `.github/copilot-instructions.md` to match current architecture.
- [ ] Add `CHANGELOGS/CHANGELOG-v0.9.md` and a changelog index.
- [ ] Confirm `.gitignore` excludes local coordinates, wallpaper assets, and build outputs.
- [ ] Review `git status --short`, `git diff --check`, and staged changes before pushing.
- [ ] Confirm version metadata and changelog match the actual changes.

## Redistribution and future release considerations

- [ ] Resolve upstream source and derived-binary redistribution rights before publishing full-source packages or binaries (see `NOTICE.md`).
- [ ] Confirm authorisation for original contributions covered by the repository's MIT licence.
- [ ] Review signing, notarisation, and relocatable installation before distributing an app bundle.

**v0.9.0 is a source-code cleanup milestone, not evidence that packaged binary distribution is authorised or ready.**
