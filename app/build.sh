#!/bin/bash
# Build Corsair Ctrl.app. Needs Xcode or the Command Line Tools.
#   bash app/build.sh
# The app is signed with a stable identity when one exists, so the Accessibility
# permission survives rebuilds. Set CODESIGN_IDENTITY to choose one; otherwise the first
# "Apple Development" identity in the keychain is used. With none, the signature is
# ad hoc and Accessibility must be re-approved after every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Corsair Ctrl.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

xcrun swiftc -O -target "$(uname -m)-apple-macos14.0" -o "$APP/Contents/MacOS/CorsairCtrl" Sources/*.swift \
  -framework Cocoa -framework WebKit -framework Network -framework ApplicationServices \
  -framework EventKit -framework ServiceManagement

cp -R web/. "$APP/Contents/Resources/web/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.woodwerd.corsairctrl</string>
  <key>CFBundleName</key><string>Corsair Ctrl</string>
  <key>CFBundleDisplayName</key><string>Corsair Ctrl</string>
  <key>CFBundleExecutable</key><string>CorsairCtrl</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.8</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSAppleEventsUsageDescription</key><string>Corsair Ctrl shows what is playing in Spotify and Music, and controls playback from the Edge panel.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Corsair Ctrl shows your next calendar event on the Corsair panel.</string>
  <key>NSCalendarsUsageDescription</key><string>Corsair Ctrl shows your next calendar event on the Corsair panel.</string>
</dict>
</plist>
PLIST

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier com.woodwerd.corsairctrl "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (no signing identity found)."
fi
echo "Built $(pwd)/$APP"
echo "Run:  open \"$(pwd)/$APP\""
echo "Quit: Settings > Quit on the panel, or: pkill -x CorsairCtrl"
