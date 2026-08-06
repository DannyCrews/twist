#!/bin/bash
# Assembles build/Twist.app from a release build.
#
# SwiftPM produces a bare executable plus a Twist_Twist.bundle of resources. macOS needs a
# real bundle for a Dock icon, a menu bar, and window activation, and Xcode is not involved
# here (its licence is unaccepted on this machine), so the bundle is laid out by hand.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
APP="build/Twist.app"
BIN_DIR=".build/arm64-apple-macosx/$CONFIG"

echo "building ($CONFIG)…"
swift build -c "$CONFIG" --product Twist

if [[ ! -f "$BIN_DIR/Twist_Twist.bundle/lexicon.twist" ]]; then
    echo "error: lexicon.twist missing — run 'make dict' first" >&2
    exit 1
fi

echo "assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Twist" "$APP/Contents/MacOS/Twist"
# The lexicon goes in flat rather than as SwiftPM's Twist_Twist.bundle: that directory has no
# Info.plist, so codesign refuses the app with "bundle format unrecognized" and takes the whole
# script down under set -e. LexiconLoader looks in Contents/Resources first for this reason.
cp "$BIN_DIR/Twist_Twist.bundle/lexicon.twist" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Twist</string>
    <key>CFBundleDisplayName</key>       <string>Twist</string>
    <key>CFBundleExecutable</key>        <string>Twist</string>
    <key>CFBundleIdentifier</key>        <string>net.crews.twist</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for Gatekeeper to run it locally, and required on Apple silicon.
# Not silenced — a signing failure here used to abort the script with no output at all.
codesign --force --sign - --timestamp=none "$APP"

echo "built $APP"
