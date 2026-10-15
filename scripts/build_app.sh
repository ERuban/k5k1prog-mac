#!/bin/bash
# Builds "K5K1 Prog.app" (universal arm64 + x86_64) into the repository root.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64 --product K5K1Prog
BIN="$(swift build -c release --arch arm64 --arch x86_64 --product K5K1Prog --show-bin-path)/K5K1Prog"

# single source of truth for the version: K5.version in Sources/K5Core/Constants.swift
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/K5Core/Constants.swift)"
[ -n "$VERSION" ] || { echo "error: K5.version not found in Constants.swift" >&2; exit 1; }

APP="K5K1 Prog.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/K5K1Prog"
# icon = the 32x32 icon embedded in k5prog_win.exe (Resources/k5prog_win.ico), scaled nearest-neighbour
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>K5K1Prog</string>
    <key>CFBundleIdentifier</key><string>local.k5k1prog</string>
    <key>CFBundleName</key><string>K5K1 Prog</string>
    <key>CFBundleDisplayName</key><string>K5K1 Prog</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"   # ad-hoc; scripts/release.sh re-signs with Developer ID
echo "built $(pwd)/$APP ($VERSION)"
