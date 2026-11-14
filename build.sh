#!/bin/zsh
# Compile SyncDoctor (arm64) et assemble build/SyncDoctor.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SyncDoctor.app"

swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/SyncDoctor" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# Icône
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift scripts/make_icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Signature Developer ID + runtime renforcé. Par défaut, le certificat « Developer ID Application »
# du trousseau ; SIGN_ID=- pour une signature ad hoc, ou SIGN_ID="<nom du certificat>" pour en choisir un.
SIGN_ID="${SIGN_ID:-Developer ID Application}"
if [[ "$SIGN_ID" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements Resources/SyncDoctor.entitlements --sign "$SIGN_ID" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "OK : $APP"
