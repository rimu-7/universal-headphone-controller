#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SPARKLE_DIR="$PWD/.build/sparkle-$SPARKLE_VERSION"
SPARKLE_ARCHIVE="$SPARKLE_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
mkdir -p "$SPARKLE_DIR"
if [ ! -f "$SPARKLE_ARCHIVE" ]; then
    curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 180 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        -o "$SPARKLE_ARCHIVE.download"
    mv "$SPARKLE_ARCHIVE.download" "$SPARKLE_ARCHIVE"
fi
printf '%s  %s\n' "$SPARKLE_SHA256" "$SPARKLE_ARCHIVE" | shasum -a 256 -c - >/dev/null
if [ ! -f "$SPARKLE_DIR/.verified" ]; then
    tar -xJf "$SPARKLE_ARCHIVE" -C "$SPARKLE_DIR"
    touch "$SPARKLE_DIR/.verified"
fi
codesign --verify --deep --strict "$SPARKLE_DIR/Sparkle.framework"
printf '%s\n' "$SPARKLE_DIR"
