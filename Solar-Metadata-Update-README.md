# Solar metadata update — implementation notes

This document describes the solar wallpaper implementation in `DesktopOverlay.swift` in the **MacOS-dynamic-MDM-desktop-overlay** fork. `DesktopOverlay-Solar-Metadata.swift` may be retained as a historical/reference snapshot; **`DesktopOverlay.swift` is the build entry point** and contains subsequent local filename/path fixes.

## Metadata-derived frame mappings

The mappings are based on solar metadata extracted from Apple's dynamic HEIC wallpapers. Frame numbers refer to the **original exported HEIC image indices**, not a renumbered chronological sequence.

### Landscape collections (8 frames)

The Desert, The Cliffs, The Lake and The Beach share this mapping:

| Phase | Solar altitude anchor | Frame |
| --- | ---: | ---: |
| Morning, deep night | −25° | `02` |
| Morning, before sunrise | −9° | `03` |
| Morning, horizon | 0° | `04` |
| Morning | +10° | `01` |
| Daytime peak | +25° | `05` |
| Afternoon | +10° | `06` |
| Evening, horizon | 0° | `07` |
| Evening twilight | −9° | `08` |
| Evening, deep night | −25° | `02` |

The approximate chronological sequence is **`02 → 03 → 04 → 01 → 05 → 06 → 07 → 08 → 02`**. The daytime frame `05` is shared around solar noon. Actual switching points fall between altitude anchors because the selector chooses the *nearest* anchor.

### Solar Gradients (16 frames)

Solar Gradients uses a separate 16-frame mapping:

| Morning altitude | Frame | Evening altitude | Frame |
| ---: | ---: | ---: | ---: |
| −87.6146° | `01` | −87.6146° | `01` |
| −17.1078° | `02` | −17.6982° | `16` |
| −11.1067° | `03` | −11.1970° | `15` |
| −5.3556° | `04` | −5.4458° | `14` |
| +0.1877° | `05` | +0.7510° | `13` |
| +6.0427° | `06` | +6.4451° | `12` |
| +11.9786° | `07` | +12.1375° | `11` |
| +18.4530° | `08` | +18.3632° | `10` |
| +88.4186° | `09` | +88.4186° | `09` |

The day progresses approximately **`01 → 02 → … → 09 → 10 → … → 16 → 01`**. The extreme low/high altitude anchors act as night/day endpoints in this approximation.

## Selection algorithm and caveats

1. Calculate approximate solar altitude and azimuth using the configured latitude, longitude and current time.
2. Treat azimuth **below 180°** as morning and **180° or above** as evening.
3. Select the closest altitude anchor from the appropriate set.
4. Load that numbered frame and crossfade when the selected image changes.

This is **not** Apple's exact algorithm. In particular, the fork does not decode the HEIC metadata at runtime, interpolate between source frames, or implement Apple's precise transition schedule. The morning/evening azimuth split is a simplification, and its behaviour at some latitudes or seasons may require refinement.

## Local directory and filenames

The **current `DesktopOverlay.swift`** looks in:

```text
Apple Dynamic Wallpapers/<wallpaperSet>/<wallpaperSet> - NN.jpg
```

For example:

```text
Apple Dynamic Wallpapers/
├── The Desert/
│   ├── The Desert - 01.jpg
│   ├── The Desert - 02.jpg
│   └── ... The Desert - 08.jpg
└── Solar Gradients/
    ├── Solar Gradients - 01.jpg
    └── ... Solar Gradients - 16.jpg
```

Other image extensions supported by the source may also work. The assets are **local-only** and are intentionally not shipped with the repository. Ensure the original HEIC export index is preserved in the filename.

## Private configuration

Place `wallpaper-config.json` **next to the compiled executable**:

```json
{
  "mode": "solar",
  "latitude": 0.0,
  "longitude": 0.0,
  "wallpaperSet": "The Desert",
  "crossfadeSeconds": 1.5
}
```

Replace `0.0` with your own approximate coordinates in the **ignored local file**, not in a public commit. To change wallpaper sets, change only `wallpaperSet` and make sure the matching local directory exists. For static wallpaper mode, use `"mode": "static"` and `wallpaper.jpg` alongside the executable.

## Build and run

From the repository root on macOS:

```sh
swiftc -O -framework AppKit -framework QuartzCore DesktopOverlay.swift -o DesktopOverlayDynamic
./DesktopOverlayDynamic
```

Quit the original overlay first: both variants use the same single-instance lock. The working solar image display has been tested on macOS; **automatic frame changes and crossfades still need end-to-end testing**.

## Git safety

Keep these items out of public Git history:

```gitignore
/wallpaper-config.json
/Apple Dynamic Wallpapers/
/DesktopOverlayDynamic
```

The reference Swift file and this documentation can be committed. Check that neither contains real coordinates or private local data before pushing. Review `git status --short` and `git diff --cached` before each push.
