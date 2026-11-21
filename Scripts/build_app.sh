#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "🔨 Compiling HeadphoneController (Universal: Apple Silicon arm64 + Intel x86_64)..."

SWIFT_SOURCES=(
    Sources/HeadphoneController/*/*.swift
    Sources/HeadphoneController/*/*/*.swift
)

BUILD_DIR="$DIR/.build_universal"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "  -> Compiling arm64 (Apple Silicon)..."
swiftc -O -target arm64-apple-macosx13.0 \
    -framework IOBluetooth -framework CoreBluetooth -framework CoreAudio -framework AppKit -framework SwiftUI \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/HeadphoneController_arm64"

echo "  -> Compiling x86_64 (Intel)..."
swiftc -O -target x86_64-apple-macosx13.0 \
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Successfully built Universal HeadphoneController.app at: $APP_BUNDLE"
