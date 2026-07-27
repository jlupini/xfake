#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/xfake.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/xfake "$APP/Contents/MacOS/xfake"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>xfake</string>
    <key>CFBundleIdentifier</key><string>com.jlupini.xfake</string>
    <key>CFBundleName</key><string>xfake</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force -s - "$APP"
echo "Built $APP"
