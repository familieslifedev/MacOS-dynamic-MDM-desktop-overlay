#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="DynamicDesktopManager.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library -O -framework SwiftUI -framework AppKit DynamicDesktopManager.swift -o "$APP/Contents/MacOS/DynamicDesktopManager"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DynamicDesktopManager</string>
<key>CFBundleIdentifier</key><string>dev.familieslife.DynamicDesktopManager</string>
<key>CFBundleName</key><string>Dynamic Desktop Manager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Built %s\n' "$APP"
