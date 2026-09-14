#!/bin/sh
# Builds NotchHub.app from the SwiftPM release build.
# Idempotent — safe to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="NotchHub"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

BIN="$BUILD_DIR/$APP_NAME"
if [ ! -x "$BIN" ]; then
  echo "error: release binary not found at $BIN" >&2
  exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.notchhub.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>NotchHub listens to your microphone only while you dictate.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>NotchHub turns your speech into text on this Mac while you dictate.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>NotchHub shows your next calendar event and its join link in the notch.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>NotchHub shows your next calendar event and its join link in the notch.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>NotchHub watches your Downloads folder to show download progress.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchHub reads the currently playing track from Spotify, Music, and your browser to show it in the notch.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> signing $APP_DIR"
# An ad-hoc signature's default designated requirement is the exact code hash,
# so macOS privacy settings (Accessibility, Automation, Calendar…) treat every
# rebuild as a brand-new app and its grants stop applying. Pin the requirement
# to the bundle identifier so a grant survives rebuilds.
codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.notchhub.app"' \
  "$APP_DIR"

echo "==> done: $APP_DIR"
echo "    run headless selftest:  $APP_DIR/Contents/MacOS/$APP_NAME --selftest"
echo "    run island preview:     $APP_DIR/Contents/MacOS/$APP_NAME --demo"
