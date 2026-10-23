#!/usr/bin/env python3
"""Extract the app's actual Solar enum and run repeatability/range tests using swiftc."""
from pathlib import Path
import subprocess, tempfile
src = Path('DesktopOverlay.swift').read_text()
start = src.find('private enum Solar {')
assert start >= 0, 'Solar enum not found'
opening = src.find('{', start)
depth = 0
end = None
for i in range(opening, len(src)):
    if src[i] == '{': depth += 1
    if src[i] == '}':
        depth -= 1
        if depth == 0:
            end = i + 1
            break
assert end is not None, 'Solar enum braces not balanced'
solar = src[start:end]
tests = r'''
import Foundation
func check(_ ok: Bool, _ message: String) {
    if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let fmt = ISO8601DateFormatter()
let sets = ["The Desert", "The Cliffs", "The Lake", "The Beach", "Solar Gradients"]
let coords: [(Double, Double)] = [(0,0), (53.6,-0.3), (-33.9,151.2), (64.1,-21.9)]
var count = 0
for set in sets {
    let limit = set == "Solar Gradients" ? 16 : 8
    for (lat,lon) in coords {
        for month in [1,3,6,9,12] {
            for hour in 0..<24 {
                let stamp = String(format:"2026-%02d-15T%02d:00:00Z", month, hour)
                guard let date = fmt.date(from:stamp) else { fatalError("Bad test date") }
                let a = Solar.frame(at:date,latitude:lat,longitude:lon,wallpaperSet:set)
                let b = Solar.frame(at:date,latitude:lat,longitude:lon,wallpaperSet:set)
                check(a == b, "Nondeterministic frame for \(set) \(stamp)")
                check((1...limit).contains(a), "Out-of-range frame \(a) for \(set) \(stamp)")
                let position = Solar.position(at:date,latitude:lat,longitude:lon)
                check(position.altitude.isFinite && position.azimuth.isFinite, "Nonfinite solar position")
                count += 1
            }
        }
    }
}
print("PASS: \(count) solar scenarios (range, repeatability, finite positions)")
'''
with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    (root/'main.swift').write_text('import Foundation\n'+solar+'\n'+tests)
    subprocess.run(['swiftc',str(root/'main.swift'),'-o',str(root/'solar-tests')],check=True)
    subprocess.run([str(root/'solar-tests')],check=True)
