#!/usr/bin/env bash
# make-icon.sh — Regenerate Resources/Klef.icns from the app icon SVG.
#
# Klef.icns is committed, so this only needs re-running when the artwork
# changes. bundle-app.sh copies the committed .icns and never calls this.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SOURCE="$REPO_ROOT/Resources/logo/klef-icon-brass.svg"
ICONSET="$(mktemp -d)/Klef.iconset"
OUTPUT="$REPO_ROOT/Resources/Klef.icns"

if [ ! -f "$SOURCE" ]; then
    echo "Source artwork not found: $SOURCE" >&2
    exit 1
fi

swift "$REPO_ROOT/scripts/make-iconset.swift" "$SOURCE" "$ICONSET"
iconutil --convert icns --output "$OUTPUT" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"

echo "Icon: $OUTPUT"
