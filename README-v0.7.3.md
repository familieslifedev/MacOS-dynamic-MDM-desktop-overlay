# Dynamic Desktop Manager v0.7.3 — gallery hit-testing fix

The gallery uses a resizable, scaled-to-fill NSImage. SwiftUI can hit-test the image outside its visibly clipped bounds, blocking controls above it even though they appear normal. The preview is non-interactive, so `.allowsHitTesting(false)` is applied to the image. Gallery Previous/Next buttons remain interactive.

Replace `DynamicDesktopManager.swift`, quit the existing manager, run `bash build-manager.sh`, and open `DynamicDesktopManager.app`. No overlay rebuild is required.

Test switching Wallpaper/Testing/System and selecting wallpaper collections, plus Previous/Next. If the issue remains, check with a temporarily hidden gallery to isolate layout hit-testing.

Not compiled on macOS in this environment.
