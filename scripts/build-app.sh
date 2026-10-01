#!/usr/bin/env bash
# 建置 RawViewer.app 到 build/。用法：scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="0.1.0"
swift build -c "$CONFIG"

APP="build/RawViewer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/RawViewer" "$APP/Contents/MacOS/RawViewer"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RawViewer</string>
    <key>CFBundleDisplayName</key><string>RAW Viewer</string>
    <key>CFBundleIdentifier</key><string>io.github.pito0713.rawviewer</string>
    <key>CFBundleExecutable</key><string>RawViewer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# 本機用 ad-hoc 簽章；對外發佈需改用 Developer ID 簽章與公證。
codesign --force --sign - "$APP"
echo "Built $APP"
