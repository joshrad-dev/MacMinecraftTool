#!/bin/bash
# Regenerate the packaged macOS icon from its editable SVG source.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v rsvg-convert >/dev/null; then
    echo "Install librsvg (brew install librsvg) to regenerate the icon." >&2
    exit 1
fi

ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
python3 Scripts/prepare-icon.py
rsvg-convert -w 1024 -h 1024 Resources/AppIcon.svg -o build/AppIcon-preview.png
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/AppIcon-preview.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" build/AppIcon-preview.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Updated Resources/AppIcon.icns"
