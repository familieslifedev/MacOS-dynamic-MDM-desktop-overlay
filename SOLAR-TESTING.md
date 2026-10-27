# Solar wallpaper testing

The current `DesktopOverlay.swift` already includes simulated time support. **Do not run the old `add_solar_test_mode.py` patch**; it is a historical migration script and can be removed during v0.9 cleanup.

## Build from the repository root

```sh
bash build-manager.sh
open DynamicDesktopManager.app
```

Use **Build & Restart** in the manager to compile and restart the overlay. Alternatively, compile it directly:

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
```

Stop the running overlay before manually launching a newly compiled copy; both use the same single-instance lock.

## Test using the manager

1. Open the menu bar manager and select **Testing**.
2. Try **Sunrise**, **Midday**, **Sunset**, and **Night** presets, or choose a **Custom local time** and select **Apply custom time**.
3. Confirm the desktop wallpaper changes to a plausible frame and that transitions are smooth.
4. Select **Return to Live Solar** when finished.

The preset labels are convenient test cases, **not calculated astronomical events**. In particular, **Sunset** uses a fixed local clock time. The manager's solar clock display reflects the configured clock; it does not report the frame calculated by the overlay.

## Manual simulated clock

You can also add an optional property to your local `wallpaper-config.json`:

```json
{
  "mode": "solar",
  "latitude": 0.0,
  "longitude": 0.0,
  "wallpaperSet": "The Desert",
  "crossfadeSeconds": 1.5,
  "testDateTime": "2026-06-21T06:00:00Z"
}
```

Replace coordinates locally. `testDateTime` is a UTC ISO 8601 timestamp with `Z`; convert local time to UTC if entering it manually. The overlay normally refreshes approximately once per minute, so allow time for a transition or restart it. **Remove `testDateTime` to restore live time.** Never commit the private configuration file.

Example UTC test timestamps: `2026-06-21T00:00:00Z`, `04:00:00Z`, `08:00:00Z`, `12:00:00Z`, `16:00:00Z`, and `20:00:00Z` (each with the same date and trailing `Z`). Results depend on the configured location and season.

## Automated solar checks

From the repository root:

```sh
python3 run_solar_unit_tests.py
```

This extracts the `Solar` implementation from the active Swift source, compiles a temporary Swift harness, and checks **2,400 combinations** (5 collections × 4 locations × 5 months × 24 hours) for valid frame ranges, deterministic results, and finite solar coordinates. It does **not** prove the mapping matches Apple's implementation or test GUI transitions.

## Manual regression checklist

- [ ] Live solar mode selects a plausible frame with no `testDateTime` override.
- [ ] All four landscape collections load their numbered frames.
- [ ] Solar Gradients loads its sixteen-frame collection.
- [ ] Simulated morning, midday, evening, and night select plausible frames.
- [ ] Crossfades occur without black flashes or unexpected window stacking.
- [ ] Static `wallpaper.jpg` mode still works.
- [ ] Gallery **Previous** and **Next** buttons work without changing the desktop wallpaper.
- [ ] Connecting/disconnecting displays refreshes overlays appropriately.
- [ ] Sleep/wake restores an appropriate frame.
- [ ] Missing image frames are handled without a crash; restore test files afterward.
- [ ] Invalid `testDateTime` is reported without crashing.
- [ ] **Return to Live Solar** removes the simulated clock override.
- [ ] Build, Build & Restart, Stop, and Restart behave as expected.
- [ ] Diagnostics and validation show useful results without leaking coordinates.

Record the macOS version, observed behaviour, and any issues. These are **tests to perform**, not claims that v0.9 has passed them.

## Safety

Keep `wallpaper-config.json`, `Apple Dynamic Wallpapers/`, and generated executables out of Git. Use test data that does not disclose private coordinates or device-management information.
