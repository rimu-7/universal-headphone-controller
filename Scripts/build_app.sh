#!/bin/bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

SPARKLE_DIR="$("$DIR/Scripts/prepare_sparkle.sh")"
APP_VERSION="$(cat "$DIR/VERSION")"
APP_BUILD_VERSION="${APP_BUILD_VERSION:-0}"
PUBLIC_ED_KEY="$(cat "$DIR/Config/SparklePublicKey.txt")"
python3 - "$APP_VERSION" "$APP_BUILD_VERSION" "$PUBLIC_ED_KEY" <<'PY'
import base64, re, sys
version, build, key = sys.argv[1:]
if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+(?:\.\d+){0,2}', build):
    raise SystemExit('Invalid app version or build number')
if len(base64.b64decode(key, validate=True)) != 32:
    raise SystemExit('The update public key must be a valid 32-byte Ed25519 public key')
PY

echo "🔨 Compiling HeadphoneController (Universal: Apple Silicon arm64 + Intel x86_64)..."

SWIFT_SOURCES=(
    Sources/HeadphoneController/*/*.swift
    Sources/HeadphoneController/*/*/*.swift
)

BUILD_DIR="$DIR/.build_universal"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "  -> Compiling arm64 (Apple Silicon)..."
swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 \
    -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    -framework IOBluetooth -framework CoreBluetooth -framework CoreAudio -framework AppKit -framework SwiftUI \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/HeadphoneController_arm64"

echo "  -> Compiling x86_64 (Intel)..."
swiftc -O -swift-version 5 -target x86_64-apple-macosx13.0 \
    -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    -framework IOBluetooth -framework CoreBluetooth -framework CoreAudio -framework AppKit -framework SwiftUI \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/HeadphoneController_x86_64"

echo "  -> Creating Universal 2 fat binary with lipo..."
lipo -create -output "$DIR/HeadphoneController" "$BUILD_DIR/HeadphoneController_arm64" "$BUILD_DIR/HeadphoneController_x86_64"
lipo -info "$DIR/HeadphoneController"
rm -rf "$BUILD_DIR"

APP_BUNDLE="$DIR/HeadphoneController.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "📦 Creating macOS App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$CONTENTS/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
cp "$SPARKLE_DIR/LICENSE" "$RESOURCES/Sparkle-LICENSE.txt"

cp "$DIR/HeadphoneController" "$MACOS/HeadphoneController"
chmod +x "$MACOS/HeadphoneController"

cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.user.HeadphoneController</string>
    <key>CFBundleName</key>
    <string>HeadphoneController</string>
    <key>CFBundleDisplayName</key>
    <string>Headphone Controller</string>
    <key>CFBundleExecutable</key>
    <string>HeadphoneController</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD_VERSION</string>
    <key>SUFeedURL</key>
    <string>https://github.com/rimu-7/universal-headphone-controller/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>$PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>3600</integer>
    <key>SUAutomaticallyUpdate</key>
    <false/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>SUSendProfileInfo</key>
    <false/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Headphone Controller requires Bluetooth to connect to Huawei and Edifier headphones and manage noise cancellation and battery monitoring.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Headphone Controller requires Bluetooth to communicate with your headphones.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "🔏 Signing application bundle (ad-hoc)..."
# Preserve Sparkle's nested Developer ID signatures; sign only our outer app ad-hoc.
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "✅ Successfully built Universal HeadphoneController.app at: $APP_BUNDLE"
