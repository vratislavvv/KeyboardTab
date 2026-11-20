#!/bin/zsh
# Builds KeyboardTab.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/KeyboardTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 -target arm64-apple-macos14 -o "$APP/Contents/MacOS/KeyboardTab-arm64" Sources/*.swift
swiftc -O -swift-version 5 -target x86_64-apple-macos14 -o "$APP/Contents/MacOS/KeyboardTab-x86_64" Sources/*.swift
lipo -create -output "$APP/Contents/MacOS/KeyboardTab" "$APP"/Contents/MacOS/KeyboardTab-*
rm "$APP"/Contents/MacOS/KeyboardTab-*

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x KeyboardTab 2>/dev/null || true
  # Let the old copy finish quitting (it restores macOS's settings) before starting the new one.
  for _ in {1..20}; do pgrep -x KeyboardTab >/dev/null || break; sleep 0.25; done
  rm -rf /Applications/KeyboardTab.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/KeyboardTab.app"
  # Every build has a new signature, so macOS no longer honours the old Accessibility approval
  # (it stays listed but silently doesn't work). Clear it so the app can ask again right away.
  tccutil reset Accessibility local.keyboardtab >/dev/null 2>&1 || true
  open /Applications/KeyboardTab.app
  echo "Started KeyboardTab. Allow Accessibility access when asked."
fi
