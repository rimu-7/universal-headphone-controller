#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP="$DIR/HeadphoneController.app"

if [ ! -d "$APP" ]; then
    echo "App bundle not found. Building first..."
    "$DIR/Scripts/build_app.sh"
fi

echo "🚀 Launching HeadphoneController in Menu Bar..."
open "$APP"
echo "✨ Running! Check your macOS Menu Bar (top-right)."
