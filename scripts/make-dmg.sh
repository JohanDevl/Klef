#!/usr/bin/env bash
# make-dmg.sh — Package Klef.app into a distributable disk image.
#
# Run after scripts/bundle-app.sh. Produces dist/Klef-<version>.dmg containing
# Klef.app next to an /Applications symlink, so the drag-to-install gesture
# works from the mounted volume.
#
# Signing tiers (see README → Installing):
#
#   default          Whatever signature bundle-app.sh applied — ad-hoc unless
#                    MACOS_SIGN_IDENTITY was set. The DMG itself is unsigned.
#                    Gatekeeper blocks downloads of this until approved by hand.
#
#   MACOS_SIGN_IDENTITY set
#                    The .app is Developer ID signed with the hardened runtime
#                    (done by bundle-app.sh); this script also signs the DMG.
#
#   + notarization credentials
#                    Additionally submits the DMG to Apple and staples the
#                    ticket, so it opens with no warning at all. Requires:
#                      AC_NOTARY_KEY_ID, AC_NOTARY_ISSUER_ID, AC_NOTARY_KEY_PATH
#                    (App Store Connect API key — .p8 file path).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP="$REPO_ROOT/Klef.app"
OUTPUT_DIR="$REPO_ROOT/dist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            shift
            APP="${1:?--app requires a path to Klef.app}"
            ;;
        --output)
            shift
            OUTPUT_DIR="${1:?--output requires a directory argument}"
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--app PATH] [--output DIR]" >&2
            exit 1
            ;;
    esac
    shift
done

if [ ! -d "$APP" ]; then
    echo "$APP not found. Run: swift build -c release && ./scripts/bundle-app.sh" >&2
    exit 1
fi

# Read the version back out of the built bundle rather than version.txt, so the
# filename can never disagree with what the app reports about itself.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist")"

mkdir -p "$OUTPUT_DIR"
DMG="$OUTPUT_DIR/Klef-$VERSION.dmg"
rm -f "$DMG"

# Stage in a temp dir so the DMG root holds exactly the two entries we want.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/Klef.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "Klef $VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"

if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    echo "Signing disk image with Developer ID: $MACOS_SIGN_IDENTITY"
    codesign --force --timestamp --sign "$MACOS_SIGN_IDENTITY" "$DMG"

    if [ -n "${AC_NOTARY_KEY_ID:-}" ] && \
       [ -n "${AC_NOTARY_ISSUER_ID:-}" ] && \
       [ -n "${AC_NOTARY_KEY_PATH:-}" ]; then
        echo "Submitting to Apple notary service (this takes a few minutes)…"
        xcrun notarytool submit "$DMG" \
            --key      "$AC_NOTARY_KEY_PATH" \
            --key-id   "$AC_NOTARY_KEY_ID" \
            --issuer   "$AC_NOTARY_ISSUER_ID" \
            --wait

        # Staples the ticket into the DMG so first launch works offline.
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
        echo "Notarized and stapled."
    else
        echo "Notary credentials absent — DMG is signed but NOT notarized." >&2
    fi
else
    echo "MACOS_SIGN_IDENTITY unset — ad-hoc build. Gatekeeper will warn on download." >&2
fi

# Checksum so users can verify the download against the release notes.
# Computed from inside the output directory so the file records the bare
# filename: an absolute build path would make `shasum -c` fail for everyone
# who downloads it.
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")

echo "DMG: $DMG"
