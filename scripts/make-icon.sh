#!/usr/bin/env bash
# make-icon.sh — Regenerate the rasterised icon artefacts from the icon SVG.
#
# Produces:
#   Resources/Klef.icns          the app bundle icon (copied by bundle-app.sh)
#   Resources/logo/klef-icon.png the 512px README header image
#
# Both are committed, so this only needs re-running when the artwork changes.
# The README uses the PNG rather than the SVG because GitHub sanitises inline
# SVG and renders it unpredictably against dark backgrounds.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SOURCE="$REPO_ROOT/Resources/logo/klef-icon-brass.svg"
ICONSET="$(mktemp -d)/Klef.iconset"
OUTPUT="$REPO_ROOT/Resources/Klef.icns"
PNG="$REPO_ROOT/Resources/logo/klef-icon.png"

if [ ! -f "$SOURCE" ]; then
    echo "Source artwork not found: $SOURCE" >&2
    exit 1
fi

swift "$REPO_ROOT/scripts/make-iconset.swift" "$SOURCE" "$ICONSET"
iconutil --convert icns --output "$OUTPUT" "$ICONSET"

# The 512px entry is already rendered from the vector at that size, so lift it
# straight out of the iconset instead of downscaling the 1024 raster.
cp "$ICONSET/icon_512x512.png" "$PNG"

rm -rf "$(dirname "$ICONSET")"

echo "Icon: $OUTPUT"
echo "PNG:  $PNG"
