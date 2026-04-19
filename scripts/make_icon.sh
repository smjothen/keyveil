#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
SRC="$ROOT/icon.svg"
ICONSET="$ROOT/Keyveil.iconset"

mkdir -p "$ICONSET"

sizes=(16 32 64 128 256 512 1024)
for s in "${sizes[@]}"; do
    rsvg-convert -w $s -h $s "$SRC" -o "$ICONSET/icon_${s}x${s}.png"
done

# Retina (@2x) slots
cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ROOT/Keyveil.icns"
rm -rf "$ICONSET"
echo "Created Keyveil.icns"
