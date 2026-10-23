# Solar metadata update — DesktopOverlay

This update replaces the eight-frame assumed scheduler with metadata-derived frame mappings:

- The Desert, The Cliffs, The Lake, The Beach: original HEIC frame order `02 → 03 → 04 → 01 → 05 → 06 → 07 → 08 → 02`, with frame 05 used on both sides of solar noon.
- Solar Gradients: 16 original HEIC frames, numbered `01` through `16` in sunrise-to-night order, with 01 as the deep-night anchor.

The selector computes solar altitude and azimuth and chooses the nearest metadata altitude anchor on the morning or evening side. It is **an approximation** of Apple's selection algorithm, not an exact reproduction. In particular, it doesn't replicate Apple's interpolation between metadata positions, and it assumes the exported frame numbers match the HEIC indices.

## Install in your fork

Copy `DesktopOverlay-Solar-Metadata.swift` to `DesktopOverlay.swift` in the fork, replacing that file. The app now reads **`wallpaper-config.json`**, matching your rename. Keep your actual file private and ignored by Git. Do not commit coordinates or extracted Apple images.

## Example private configuration

```json
{
  "mode": "solar",
  "latitude": 0.0,
  "longitude": 0.0,
  "wallpaperSet": "The Desert",
  "crossfadeSeconds": 1.5
}
```

Replace 0.0 values locally with your approximate location. Set `wallpaperSet` to `The Cliffs`, `The Lake`, `The Beach`, or `Solar Gradients` to select another collection.

## Assets

Place images alongside the compiled executable, in `dynamic/<wallpaperSet>/01.jpg` etc. Landscape collections need eight frames; Solar Gradients needs sixteen. The images are *not* bundled in this repository.

## Build (on macOS)

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
```

Keep the original executable and source as a backup. The original and modified versions share a single-instance lock; stop the original before testing the new one. The existing multi-monitor overlay, static mode, file watching and crossfades are retained.
