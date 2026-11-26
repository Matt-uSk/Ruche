#!/bin/bash
# Compile Ruche et assemble build/Ruche.app (signature ad hoc, usage local).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Ruche"

APP="build/Ruche.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ruche"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Signature : certificat local stable si présent (évite que macOS redemande l'accès
# au trousseau et les autorisations à chaque recompilation), sinon ad hoc.
SIGN_ID="${RUCHE_SIGN_ID:-Ruche Local}"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
    codesign --force --sign "$SIGN_ID" "$APP"
    echo "🔏 Signé avec le certificat « $SIGN_ID »"
else
    codesign --force --sign - "$APP"
    echo "⚠️  Signature ad hoc (certificat « $SIGN_ID » introuvable, voir README)"
fi

echo "✅ $APP prêt — lance-le avec : open \"$APP\" (ou copie-le dans /Applications)"
