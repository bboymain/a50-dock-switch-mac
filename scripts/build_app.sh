#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release

APP="A50DockSwitch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/A50DockSwitch" "$APP/Contents/MacOS/A50DockSwitch"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>A50DockSwitch</string>
    <key>CFBundleDisplayName</key><string>A50 Dock Switch</string>
    <key>CFBundleIdentifier</key><string>com.bboymain.A50DockSwitch</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>A50DockSwitch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
</dict>
</plist>
EOF

echo "Built $APP"

# Keep an installed copy so the app shows up in Spotlight/Launchpad. The bundle
# in the repo is rewritten from scratch each build, so without this the copy in
# /Applications would silently go stale.
DEST="/Applications/A50DockSwitch.app"
if [ -w "$(dirname "$DEST")" ]; then
    if pgrep -f "$DEST" >/dev/null 2>&1; then
        echo "Quitting running copy to replace it..."
        pkill -f "$DEST"
        sleep 1
    fi
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    echo "Installed $DEST"
else
    echo "Skipped install ($(dirname "$DEST") not writable)"
fi
