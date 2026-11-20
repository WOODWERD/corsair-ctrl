#!/bin/bash
# Build the Edge Ctrl spike. Needs Xcode Command Line Tools (xcode-select --install).
# Produces the bare binary (./EdgeCtrlSpike) and an app bundle ("Edge Ctrl Spike.app").
# Run the bundle: macOS then attaches the Accessibility permission to the app itself
# instead of to whichever terminal launched it.
set -euo pipefail
cd "$(dirname "$0")"
xcrun swiftc -O -o EdgeCtrlSpike main.swift \
  -framework Cocoa -framework WebKit -framework Network -framework ApplicationServices

APP="Edge Ctrl Spike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp EdgeCtrlSpike "$APP/Contents/MacOS/EdgeCtrlSpike"
cp index.html "$APP/Contents/Resources/index.html"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.woodwerd.edgectrl.spike</string>
  <key>CFBundleName</key><string>Edge Ctrl Spike</string>
  <key>CFBundleExecutable</key><string>EdgeCtrlSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
# Sign with a stable identity when one exists, so the Accessibility permission
# survives rebuilds. Set CODESIGN_IDENTITY to choose one; otherwise the first
# "Apple Development" identity in the keychain is used. With none, fall back to an
# ad-hoc signature, which changes on every rebuild and needs re-approving each time.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier com.woodwerd.edgectrl.spike "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (no signing identity found)."
fi
echo "Built $(pwd)/$APP — run it with: open \"$(pwd)/$APP\""
echo "Quit it with: pkill -x EdgeCtrlSpike"
