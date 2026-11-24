#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SPARKLE_KEY_FILE:?Set SPARKLE_KEY_FILE to the private signing-key file}"
: "${UPDATE_DOWNLOAD_PREFIX:?Set UPDATE_DOWNLOAD_PREFIX to the immutable release download URL}"
SPARKLE_DIR="$(./Scripts/prepare_sparkle.sh)"
ASSETS_DIR="$PWD/release-assets"
ARCHIVE="$ASSETS_DIR/HeadphoneController-update.zip"
# Fail before publishing if the secret belongs to a different public key.
SIGNATURE="$("$SPARKLE_DIR/bin/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" -p "$ARCHIVE")"
mkdir -p .build/update-tools
swiftc -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$PWD/.build/update-module-cache}" \
    Scripts/verify_update.swift -o .build/update-tools/verify_update
.build/update-tools/verify_update "$ARCHIVE" "$SIGNATURE" Config/SparklePublicKey.txt
# Keep the manual DMG outside the source directory so it is not added as a second update item.
FEED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/headphone-update-feed.XXXXXX")"
trap 'rm -rf "$FEED_DIR"' EXIT
cp "$ARCHIVE" "$FEED_DIR/"
if [ -n "${UPDATE_RELEASE_NOTES_FILE:-}" ]; then
    cp "$UPDATE_RELEASE_NOTES_FILE" "$FEED_DIR/HeadphoneController-update.txt"
fi
"$SPARKLE_DIR/bin/generate_appcast" --ed-key-file "$SPARKLE_KEY_FILE" \
    --download-url-prefix "$UPDATE_DOWNLOAD_PREFIX" --maximum-deltas 0 --embed-release-notes \
    --link 'https://github.com/rimu-7/universal-headphone-controller/releases' "$FEED_DIR"
cp "$FEED_DIR/appcast.xml" "$ASSETS_DIR/appcast.xml"
"$SPARKLE_DIR/bin/sign_update" --verify --ed-key-file "$SPARKLE_KEY_FILE" "$ASSETS_DIR/appcast.xml"
python3 Scripts/validate_release.py "$ASSETS_DIR" "$UPDATE_DOWNLOAD_PREFIX"
(cd "$ASSETS_DIR" && shasum -a 256 HeadphoneController.dmg HeadphoneController-update.zip appcast.xml > SHA256SUMS)
