#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/SimplexFlame.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Sources/SimplexFlame/Flame.metal "$APP/Contents/Resources/"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    Sources/SimplexFlame/Renderer.swift Sources/SimplexFlame/main.swift \
    -o "$APP/Contents/MacOS/SimplexFlame"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SimplexFlame</string>
<key>CFBundleIdentifier</key><string>local.simplexflame.wallpaper</string>
<key>CFBundleName</key><string>SimplexFlame</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
