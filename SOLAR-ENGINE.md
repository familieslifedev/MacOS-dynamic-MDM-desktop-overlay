# Solar engine and frame mappings

This document describes the solar-selection implementation in the active `DesktopOverlay.swift` source. It replaces the historical `Solar-Metadata-Update-README.md`; `DesktopOverlay-Solar-Metadata.swift` is not required to build the application.

## How selection works

1. Calculate approximate solar altitude and azimuth from the configured latitude, longitude, and effective clock time.
2. Use azimuth below 180° for the morning anchor set, or 180° and above for the evening set.
3. Choose the anchor with the closest altitude.
4. Load the corresponding image by its original HEIC export index and crossfade if the selected image changes.

This is a nearest-anchor approximation, **not** Apple's exact dynamic-wallpaper algorithm. The app does not decode HEIC solar metadata at runtime, interpolate source frames, or reproduce Apple's proprietary transition schedule. The azimuth split is simplified and may behave imperfectly at certain latitudes or seasons. A frame may switch at the midpoint between two altitude anchors, rather than at an anchor's exact altitude.

## Landscape collections: eight frames

The Desert, The Cliffs, The Lake, and The Beach share these mappings:

| Phase | Solar altitude anchor | Frame |
| --- | ---: | ---: |
| Morning, deep night | −25° | `02` |
| Morning, before sunrise | −9° | `03` |
| Morning, horizon | 0° | `04` |
| Morning | +5° | `01` |
| Daytime peak | +25° | `05` |
| Afternoon | +5° | `06` |
| Evening, horizon | 0° | `07` |
| Evening twilight | −9° | `08` |
| Evening, deep night | −25° | `02` |

Approximate chronological sequence: **`02 → 03 → 04 → 01 → 05 → 06 → 07 → 08 → 02`**. Frame `05` is shared around solar noon. These are **original exported image indices**, not chronological renumbering.

## Solar Gradients: sixteen frames

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

Approximate sequence: **`01 → 02 → … → 09 → 10 → … → 16 → 01`**. The extreme anchors serve as approximate night/day endpoints.

## Asset paths

The active overlay looks for collection frames alongside the executable, under:

```text
Apple Dynamic Wallpapers/<wallpaperSet>/<wallpaperSet> - NN.jpg
```

For example: `Apple Dynamic Wallpapers/The Desert/The Desert - 04.jpg`. The source supports additional image extensions. Preserve the original exported HEIC indices. Assets are local-only and are not bundled in the repository.

## Configuration and test clock

The local `wallpaper-config.json` holds `mode`, `latitude`, `longitude`, `wallpaperSet`, and `crossfadeSeconds`. An optional UTC ISO 8601 `testDateTime` overrides the live clock for testing. Remove it to restore live solar selection. See [SOLAR-TESTING.md](SOLAR-TESTING.md).

## Testing and known limits

Use `python3 run_solar_unit_tests.py` from the repository root to check repeatability, finite solar coordinates, and frame bounds. This does not establish visual correctness or validate crossfades. Manual sunrise, sunset, sleep/wake, display, and static-mode checks are still necessary before a stable release.

Do not commit private coordinates or copyrighted wallpaper images. See [NOTICE.md](NOTICE.md).
