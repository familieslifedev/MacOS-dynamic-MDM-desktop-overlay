#!/usr/bin/env python3
"""Idempotently add optional ISO8601 solar clock override to DesktopOverlay.swift."""
from pathlib import Path
p = Path('DesktopOverlay.swift')
s = p.read_text()
if 'testDateTime' in s:
    print('testDateTime already present; no changes made.')
    raise SystemExit(0)
old = '    var crossfadeSeconds: Double = 1.5'
new = old + '\n    var testDateTime: String? = nil  // Optional ISO 8601 UTC test clock; omit for live sun'
assert s.count(old) == 1, 'Could not uniquely locate config property'
s = s.replace(old, new, 1)
old = 'case mode, latitude, longitude, wallpaperSet, crossfadeSeconds'
new = 'case mode, latitude, longitude, wallpaperSet, crossfadeSeconds, testDateTime'
assert s.count(old) == 1, 'Could not locate CodingKeys'
s = s.replace(old, new, 1)
old = '        crossfadeSeconds = try c.decodeIfPresent(Double.self, forKey: .crossfadeSeconds) ?? 1.5'
new = old + '\n        testDateTime = try c.decodeIfPresent(String.self, forKey: .testDateTime)'
assert s.count(old) == 1, 'Could not locate config decoder'
s = s.replace(old, new, 1)
old = '            let frame = Solar.frame(at: Date(), latitude: lat, longitude: lon, wallpaperSet: config.wallpaperSet)'
new = '''            // Developer-only simulated clock. A malformed value is rejected rather
            // than silently showing live time and producing misleading test results.
            let solarDate: Date
            if let override = config.testDateTime {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let parsed = formatter.date(from: override)
                    ?? ISO8601DateFormatter().date(from: override)
                guard let parsed else {
                    logger.error("Invalid testDateTime; use ISO 8601, e.g. 2026-06-21T06:00:00Z")
                    return nil
                }
                solarDate = parsed
            } else {
                solarDate = Date()
            }
            let frame = Solar.frame(at: solarDate, latitude: lat, longitude: lon, wallpaperSet: config.wallpaperSet)
            if config.testDateTime != nil {
                logger.notice("Solar test clock active; selected frame \\(frame)")
            }'''
assert s.count(old) == 1, 'Could not uniquely locate solar frame selection'
s = s.replace(old, new, 1)
p.write_text(s)
print('Added optional testDateTime to DesktopOverlay.swift. Compile on your Mac.')
