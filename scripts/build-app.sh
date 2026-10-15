#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/AIConsumeStatusBar"
APP="build/AIConsumeStatusBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AIConsumeStatusBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign -s - --force "$APP"
echo "Built $APP"
