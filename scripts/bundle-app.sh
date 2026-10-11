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
    echo "Resources/Info.plist not found — check repo state." >&2
    exit 1
fi

# Marketing version: version.txt is the single source of truth, maintained by
# release-please. Resources/Info.plist only carries a placeholder.
VERSION_FILE="$REPO_ROOT/version.txt"
if [ ! -f "$VERSION_FILE" ]; then
    echo "version.txt not found — it is the source of truth for CFBundleShortVersionString." >&2
    exit 1
fi
MARKETING_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# Build number: commit count is monotonic and identical for a given commit
# whether built locally or in CI. Falls back to 0 outside a git checkout
# (e.g. a source tarball), which is fine — only the App Store cares.
BUILD_NUMBER="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"

# Committed artefact — regenerate with scripts/make-icon.sh when the artwork changes.
ICON="$REPO_ROOT/Resources/Klef.icns"
if [ ! -f "$ICON" ]; then
    echo "Resources/Klef.icns not found — run scripts/make-icon.sh." >&2
    exit 1
fi

# Shipped inside the bundle: MIT asks for the notice to accompany every copy,
# and Settings → About reads it from there.
LICENSE_FILE="$REPO_ROOT/LICENSE"
if [ ! -f "$LICENSE_FILE" ]; then
    echo "LICENSE not found — it is bundled into Klef.app and must exist." >&2
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
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY"     "$BUNDLE/Contents/MacOS/klef"
chmod +x         "$BUNDLE/Contents/MacOS/klef"
cp "$INFO_PLIST" "$BUNDLE/Contents/Info.plist"
# Must land before codesign below, or the signature won't seal Contents/Resources.
cp "$ICON"       "$BUNDLE/Contents/Resources/Klef.icns"
cp "$LICENSE_FILE" "$BUNDLE/Contents/Resources/LICENSE"

# Stamp the real versions into the bundled copy. PlistBuddy rather than sed so a
# malformed substitution fails loudly instead of producing an unparseable plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" \
                        -c "Set :CFBundleVersion $BUILD_NUMBER" \
                        "$BUNDLE/Contents/Info.plist"

# PkgInfo: exactly 8 bytes, no newline
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Code signature.
#
# Default is ad-hoc (`-`): macOS will run the app locally, but a *downloaded*
# build carries the quarantine bit and Gatekeeper blocks it until the user
# approves it by hand (see README → Installing).
#
# Set MACOS_SIGN_IDENTITY to a Developer ID Application identity to produce a
# distributable build instead. That also enables the hardened runtime, which
# notarization requires. scripts/make-dmg.sh handles notarize + staple.
#
# --deep signs nested code objects (frameworks, helpers) — none today, but it
# keeps the call forward-compatible.
if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    echo "Signing with Developer ID: $MACOS_SIGN_IDENTITY"
    codesign --force --deep --timestamp --options runtime \
             --sign "$MACOS_SIGN_IDENTITY" "$BUNDLE"
else
    codesign --force --deep --sign - "$BUNDLE"
fi

codesign --verify --strict --verbose=2 "$BUNDLE"

echo "Bundle:  $BUNDLE"
echo "Binary:  $BINARY"
echo "Version: $MARKETING_VERSION ($BUILD_NUMBER)"
echo "To launch: open \"$BUNDLE\""
