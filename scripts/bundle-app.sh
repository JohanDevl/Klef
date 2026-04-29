#!/usr/bin/env bash
# bundle-app.sh — Wrap the SPM-built klef binary into Klef.app.
#
# Run after `swift build` (debug) or `swift build -c release`.
#
# Re-run after every rebuild: the binary's code-sign hash changes, so macOS
# will re-prompt for Input Monitoring permission (same caveat as the
# LaunchAgent path in README.md).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Refuse to bundle while a swift build is mid-flight — would embed a
# half-written binary into the .app bundle.
if pgrep -f "swift-build" >/dev/null 2>&1 || pgrep -f "swift build" >/dev/null 2>&1; then
    echo "swift build appears to be running — wait for it to finish before bundling." >&2
    exit 1
fi

# Parse flags
OUTPUT_DIR="$REPO_ROOT"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            shift
            OUTPUT_DIR="${1:?--output requires a directory argument}"
            ;;
        --force)
            FORCE=1
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--output DIR] [--force]" >&2
            exit 1
            ;;
    esac
    shift
done

# Find binary: prefer release, fall back to debug
if [ -f "$REPO_ROOT/.build/release/klef" ]; then
    BINARY="$REPO_ROOT/.build/release/klef"
elif [ -f "$REPO_ROOT/.build/debug/klef" ]; then
    BINARY="$REPO_ROOT/.build/debug/klef"
else
    echo "No built binary found. Run: swift build -c release" >&2
    exit 1
fi

INFO_PLIST="$REPO_ROOT/Resources/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    echo "Resources/Info.plist not found — run task #12 first or check repo state." >&2
    exit 1
fi

BUNDLE="$OUTPUT_DIR/Klef.app"

if [ -e "$BUNDLE" ]; then
    if [ "$FORCE" -eq 1 ]; then
        rm -rf "$BUNDLE"
    else
        echo "$BUNDLE already exists. Use --force to overwrite." >&2
        exit 1
    fi
fi

# Build bundle structure
mkdir -p "$BUNDLE/Contents/MacOS"

cp "$BINARY"     "$BUNDLE/Contents/MacOS/klef"
chmod +x         "$BUNDLE/Contents/MacOS/klef"
cp "$INFO_PLIST" "$BUNDLE/Contents/Info.plist"

# PkgInfo: exactly 8 bytes, no newline
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Ad-hoc code signature so macOS will run it without Developer ID.
# --deep signs nested code objects (frameworks, helpers) — none in V0.3
# but makes the call forward-compatible.
codesign --force --deep --sign - "$BUNDLE"

echo "Bundle: $BUNDLE"
echo "Binary: $BINARY"
echo "To launch: open \"$BUNDLE\""
