#!/bin/bash
# Builds MinecraftHelper and assembles a runnable "MacMinecraftTool.app".
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

# Compile all native icon appearances, plus the legacy macOS fallback.
# Requires Xcode 26 or later (Icon Composer support).
mkdir -p build/NativeIcon
xcrun actool Resources/AppIcon.icon \
    --compile build/NativeIcon \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist build/NativeIcon/Info.plist \
    --output-format human-readable-text

APP="build/MacMinecraftTool.app"
if [ -d "$APP" ]; then
    trash "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MinecraftHelper "$APP/Contents/MacOS/MinecraftHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/NativeIcon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp build/NativeIcon/Assets.car "$APP/Contents/Resources/Assets.car"

# Ad-hoc signature: enough for TCC to track the app, but macOS treats each
# rebuild as a new app — re-grant Accessibility access after rebuilding.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run with: open \"$APP\""
