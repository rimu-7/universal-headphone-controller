#!/bin/bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

# 1. Ensure Universal app is built
if [ "${SKIP_APP_BUILD:-0}" != 1 ]; then
    "$DIR/Scripts/build_app.sh"
fi

APP_BUNDLE="$DIR/HeadphoneController.app"
DMG_PATH="$DIR/HeadphoneController.dmg"
STAGING_DIR="$DIR/.dmg_staging"
TEMP_DMG="$DIR/HeadphoneController.tmp.dmg"
trap 'rm -rf "$STAGING_DIR" "$TEMP_DMG"' EXIT
codesign --verify --deep --strict "$APP_BUNDLE"

echo "📀 Preparing DMG Staging Area..."
rm -rf "$STAGING_DIR" "$TEMP_DMG"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 Creating Universal DMG Image (HeadphoneController.dmg)..."
hdiutil create \
    -volname "Headphone Controller" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$TEMP_DMG"

rm -rf "$STAGING_DIR"

echo "🔏 Signing DMG..."
codesign --force --sign - "$TEMP_DMG"
codesign --verify "$TEMP_DMG"
mv -f "$TEMP_DMG" "$DMG_PATH"

echo "🎉 Universal DMG successfully built at: $DMG_PATH"
ls -lh "$DMG_PATH"
