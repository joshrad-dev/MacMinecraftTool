#!/bin/bash
# Builds MinecraftHelper and assembles a runnable "Minecraft Helper.app".
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Minecraft Helper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MinecraftHelper "$APP/Contents/MacOS/MinecraftHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for TCC to track the app, but macOS treats each
# rebuild as a new app — re-grant Accessibility access after rebuilding.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run with: open \"$APP\""
