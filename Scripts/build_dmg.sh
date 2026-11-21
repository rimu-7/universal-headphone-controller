#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

# 1. Ensure Universal app is built
"$DIR/Scripts/build_app.sh"

APP_BUNDLE="$DIR/HeadphoneController.app"
DMG_PATH="$DIR/HeadphoneController.dmg"
STAGING_DIR="$DIR/.dmg_staging"

echo "📀 Preparing DMG Staging Area..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 Creating Universal DMG Image (HeadphoneController.dmg)..."
hdiutil create \
    -volname "Headphone Controller" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "🔏 Signing DMG..."
codesign --force --sign - "$DMG_PATH"

echo "🎉 Universal DMG successfully built at: $DMG_PATH"
ls -lh "$DMG_PATH"
