# Dynamic Desktop Manager v0.4 (macOS test build)

Replaces only `DynamicDesktopManager.swift`; existing `DesktopOverlay.swift`, private config, and wallpaper images remain unchanged. Keep a backup of v0.3 first.

## Install
Copy `DynamicDesktopManager.swift` and `build-manager.sh` into the repo root. Quit Manager, run `./build-manager.sh`, then `open DynamicDesktopManager.app`.

## New
- Wallpaper / Testing / System segmented tabs
- System: launch manager at login (ServiceManagement registration; may require a signed/installed app or macOS approval)
- Optional start overlay when manager opens
- Optional limited auto-recovery for unexpected exits (only while manager is running)
- Sleep/wake status check; the overlay's own timer handles frame refresh
- Configuration diagnostics and in-memory manager event history

## Important caveats
- Launch at login uses `SMAppService.mainApp` and can fail for unsigned ad-hoc builds. macOS may require enabling it in System Settings > General > Login Items. The manager shows an error rather than claiming success.
- The diagnostics report the configured wallpaper set and image count, **not** the overlay's exact active frame (the overlay does not expose that information).
- Auto-recovery is intentionally conservative; don't rely on it as a system service.
- The event list is session-only and excludes private coordinates.
- `DesktopOverlay.swift` is unchanged. Its current refresh timer is 5 seconds, despite the old comment saying once per minute.
