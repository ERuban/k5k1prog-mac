#!/bin/bash
# Builds "K5K1 Prog.app" (universal arm64 + x86_64) into the repository root.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64 --product K5K1Prog
BIN="$(swift build -c release --arch arm64 --arch x86_64 --product K5K1Prog --show-bin-path)/K5K1Prog"

# single source of truth for the version: K5.version in Sources/K5Core/Constants.swift
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/K5Core/Constants.swift)"
[ -n "$VERSION" ] || { echo "error: K5.version not found in Constants.swift" >&2; exit 1; }

# Sparkle: the feed is the appcast attached to the latest GitHub release; the public key
# is committed in Resources/SparklePublicKey.txt (the private key stays in the keychain)
FEED_URL="https://github.com/ERuban/k5k1prog-mac/releases/latest/download/appcast.xml"
# (SPARKLE_PUBLIC_KEY overrides it for local update tests). Without a key the app is built
# with updates switched off.
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$( { grep -v '^#' Resources/SparklePublicKey.txt 2>/dev/null || true; } | tr -d '[:space:]')}"
SPARKLE_KEYS=""
if [ -n "$PUBLIC_KEY" ]; then
    SPARKLE_KEYS="    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>"
else
    echo "warning: no Sparkle public key (Resources/SparklePublicKey.txt) - updates disabled in this build" >&2
fi

APP="K5K1 Prog.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/K5K1Prog"
# Sparkle (in-app updates): embed the framework and let the binary find it
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/K5K1Prog"
# icon = Resources/logo.svg on the macOS icon grid (regenerate with scripts/make_icon.py)
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>K5K1Prog</string>
    <key>CFBundleIdentifier</key><string>io.github.eruban.k5k1prog</string>
    <key>CFBundleName</key><string>K5K1 Prog</string>
    <key>CFBundleDisplayName</key><string>K5K1 Prog</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
$SPARKLE_KEYS
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"   # ad-hoc; scripts/release.sh re-signs with Developer ID
echo "built $(pwd)/$APP ($VERSION)"
