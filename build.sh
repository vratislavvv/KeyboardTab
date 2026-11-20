#!/bin/zsh
# Builds KeyboardTab.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/KeyboardTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -target arm64-apple-macos14 -o "$APP/Contents/MacOS/KeyboardTab-arm64" Sources/*.swift
swiftc -O -target x86_64-apple-macos14 -o "$APP/Contents/MacOS/KeyboardTab-x86_64" Sources/*.swift
lipo -create -output "$APP/Contents/MacOS/KeyboardTab" "$APP"/Contents/MacOS/KeyboardTab-*
rm "$APP"/Contents/MacOS/KeyboardTab-*

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x KeyboardTab 2>/dev/null || true
  rm -rf /Applications/KeyboardTab.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/KeyboardTab.app"
fi
