#!/bin/zsh
# Crée build/SyncDoctor-<version>.dmg à partir de build/SyncDoctor.app (lancer ./build.sh avant).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SyncDoctor.app"
VERSION="$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)"
DMG="build/SyncDoctor-$VERSION.dmg"
STAGE="build/dmg"
SIGN_ID="${SIGN_ID:-Developer ID Application}"

# Contenu de l'image : l'app et un raccourci vers /Applications pour le glisser-déposer.
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/SyncDoctor.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "SyncDoctor" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
codesign --verify --verbose=2 "$DMG"
echo "OK : $DMG"
