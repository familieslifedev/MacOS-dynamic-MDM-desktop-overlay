# Copilot instructions

## Build and run

This is a single-file macOS AppKit utility. It is compiled directly with `swiftc`; there is no Xcode project or Swift package. Run commands from the repository root.

```bash
# Type-check without creating an artifact
swiftc -typecheck DesktopOverlay.swift -framework AppKit

# Build the ignored executable beside the source
swiftc DesktopOverlay.swift -o DesktopOverlayLauncher -framework AppKit
```

Runtime image lookup is relative to the executable, not the current working directory. Put exactly one `wallpaper.<extension>` beside `DesktopOverlayLauncher` before launching it. For development, run `./DesktopOverlayLauncher --background` to keep the process attached and retain console output. A normal `./DesktopOverlayLauncher` invocation relaunches itself with `--background`, redirects the child's standard streams to `/dev/null`, and exits the parent process immediately.

## Architecture

- Top-level startup code implements the self-relaunch behavior before creating the shared `NSApplication`. The long-running child uses the `.accessory` activation policy, so it has no Dock or app-switcher presence.
- `AppDelegate` owns all overlay windows and the directory watcher. At launch it resolves the executable's real path, searches that directory for a supported wallpaper, builds the overlays, and subscribes to display changes.
- `resolveImagePath()` checks formats in priority order: `jpg`, `jpeg`, `png`, `heic`, `tiff`, `bmp`, `gif`, then `webp`. The first existing `wallpaper.*` file wins.
- `showOverlay(imagePath:)` replaces the entire window set with one borderless `NSWindow` per `NSScreen`. Each window sits one level above the desktop, joins all Spaces, stays stationary, ignores window cycling and mouse events, and displays a centered, proportionally scaled image over black.
- A `DispatchSourceFileSystemObject` watches the executable directory for writes and renames. Its main-queue handler reloads the first matching wallpaper. `NSApplication.didChangeScreenParametersNotification` uses the same full-window rebuild when displays are connected, disconnected, or reconfigured.

## Repository-specific conventions

- Preserve executable-relative asset discovery; launching from Finder, Terminal, and Login Items must behave identically. Do not replace it with current-working-directory lookup.
- Keep the supported extension list and its precedence synchronized between `DesktopOverlay.swift` and `README.md`. Multiple matching images are ambiguous by design, so documentation should continue to direct users to keep only one.
- Keep AppKit window creation, teardown, and refreshes on the main thread. The existing watcher deliberately targets `.main`.
- Preserve the one-window-per-screen model and rebuild all windows after wallpaper or screen changes unless a requested behavior change explicitly requires another lifecycle.
- `DesktopOverlayLauncher`, `wallpaper*`, and `overlay.log` are local artifacts ignored by Git; do not add generated binaries, user wallpapers, or runtime logs to the repository.
- Maintain compatibility with macOS Sonoma 14 or later. Avoid newer-only AppKit APIs unless the documented minimum version is intentionally raised.
- Update `README.md` when changing the build command, executable name, wallpaper naming/formats, background-launch behavior, display behavior, or Login Item workflow.
