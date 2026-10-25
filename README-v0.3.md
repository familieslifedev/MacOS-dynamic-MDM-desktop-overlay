# Dynamic Desktop Manager v0.3 — test build

Replaces v0.2 `DynamicDesktopManager.swift` and `build-manager.sh` in the repository root. Run `./build-manager.sh`, quit the old manager, then `open DynamicDesktopManager.app`.

Changes:
- Widened menu-bar panel from 350 to 470 points; preset explanation wraps instead of truncating.
- Wallpaper collection preview from the first available image in the selected folder (not necessarily the current solar frame).
- Crossfade slider from 0 to 10 seconds, in half-second increments; saves on release to `crossfadeSeconds` in the private JSON.
- Solar clock panel shows live local time or simulated local date/time, and overlay status; actual solar altitude and active frame are **not** available from the manager and are not fabricated.
- Existing v0.2 actions remain.
