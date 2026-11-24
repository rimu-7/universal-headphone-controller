#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_BUNDLE="$PWD/HeadphoneController.app"
ASSETS_DIR="$PWD/release-assets"
codesign --verify --deep --strict "$APP_BUNDLE"
mkdir -p "$ASSETS_DIR"
# ditto preserves Sparkle framework symlinks and nested code signatures.
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ASSETS_DIR/HeadphoneController-update.zip"
cp HeadphoneController.dmg "$ASSETS_DIR/HeadphoneController.dmg"
python3 - "$APP_BUNDLE/Contents/Info.plist" "$ASSETS_DIR/build-info.json" <<'PY'
import json, os, plistlib, subprocess, sys
with open(sys.argv[1], 'rb') as f:
    info = plistlib.load(f)
metadata = dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                sha=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip())
with open(sys.argv[2], 'w') as f:
    json.dump(metadata, f)
PY
