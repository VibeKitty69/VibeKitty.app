#!/bin/bash
# ┌────────────────────────────────────────────┐
# │  VibeKitty — build & run                   │
# │  Requires: macOS 12+, Xcode CLI Tools      │
# └────────────────────────────────────────────┘

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/VibeKitty/main.swift"
APP="$SCRIPT_DIR/VibeKitty.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
VIDEO="$SCRIPT_DIR/cat.mp4"

echo ""
echo "🐱  VibeKitty Builder"
echo "─────────────────────"

if ! command -v swiftc &>/dev/null; then
    echo "❌  swiftc not found."
    echo "   Install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

if [ ! -f "$VIDEO" ]; then
    echo "❌  cat.mp4 not found at: $VIDEO"
    echo "   Make sure cat.mp4 is in the same folder as this script."
    exit 1
fi

echo "✓  swiftc: $(swiftc --version 2>&1 | head -1)"
echo "✓  cat.mp4 found"
echo ""

echo "📦  Setting up app bundle..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$VIDEO" "$RES/cat.mp4"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>VibeKitty</string>
  <key>CFBundleIdentifier</key><string>com.vibekitty.app</string>
  <key>CFBundleName</key><string>VibeKitty</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

ARCH=$(uname -m)
echo "🔨  Compiling Swift (arch: $ARCH)..."
swiftc "$SOURCE" \
    -o "$MACOS/VibeKitty" \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreImage \
    -framework CoreVideo \
    -target "${ARCH}-apple-macos12.0" \
    -O

echo ""
echo "✅  Build complete!"
echo ""
echo "🚀  Launching VibeKitty..."
echo "    Look for 🐱 in your menu bar."
echo ""
open "$APP"
