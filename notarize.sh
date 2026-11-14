#!/bin/zsh
# Notarise l'app puis le .dmg auprès d'Apple et agrafe les tickets (lancer ./build.sh avant).
# Prérequis (une seule fois) : un profil de trousseau créé avec
#   xcrun notarytool store-credentials "SyncDoctor" --apple-id <identifiant Apple> --team-id <identifiant d'équipe>
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-SyncDoctor}"
APP="build/SyncDoctor.app"
ZIP="build/SyncDoctor.zip"
VERSION="$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)"
DMG="build/SyncDoctor-$VERSION.dmg"

# 1. L'app : soumise en .zip, puis ticket agrafé pour qu'elle s'ouvre même hors ligne.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$ZIP"
xcrun stapler staple "$APP"

# 2. Le .dmg : reconstruit avec l'app agrafée, puis notarisé et agrafé à son tour.
./make_dmg.sh
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "OK : $DMG"
