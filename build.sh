#!/bin/bash
# Compile Ruche et assemble build/Ruche.app.
#   ./build.sh                → app universelle (Apple Silicon + Intel)
#   NATIVE=1 ./build.sh       → architecture du Mac uniquement (plus rapide)
#   VERSION=1.2.3 ./build.sh  → inscrit ce numéro de version dans l'app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Ruche.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${NATIVE:-0}" = "1" ]; then
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/Ruche" "$APP/Contents/MacOS/Ruche"
else
    # Une compilation par architecture, copiée aussitôt (selon la version des outils Swift,
    # les deux architectures peuvent sortir au même endroit), puis fusion en binaire universel.
    TMP="build/arch"
    mkdir -p "$TMP"
    for ARCH in arm64 x86_64; do
        swift build -c release --arch "$ARCH"
        cp "$(swift build -c release --arch "$ARCH" --show-bin-path)/Ruche" "$TMP/Ruche-$ARCH"
        echo "  $ARCH → $(lipo -archs "$TMP/Ruche-$ARCH")"
    done
    lipo -create "$TMP/Ruche-arm64" "$TMP/Ruche-x86_64" -output "$APP/Contents/MacOS/Ruche"
    rm -rf "$TMP"
fi
lipo -info "$APP/Contents/MacOS/Ruche"

cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi

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
