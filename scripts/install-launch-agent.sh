#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Refuse to install while a swift build is mid-flight — would copy a path to a
# half-written binary, which launchd would respawn against once linking finishes.
if pgrep -f "swift-build" >/dev/null 2>&1 || pgrep -f "swift build" >/dev/null 2>&1; then
    echo "swift build appears to be running — wait for it to finish before installing." >&2
    exit 1
fi

# Find binary: prefer release, fall back to debug
if [ -f "$REPO_ROOT/.build/release/klef" ]; then
    BINARY_PATH="$REPO_ROOT/.build/release/klef"
elif [ -f "$REPO_ROOT/.build/debug/klef" ]; then
    BINARY_PATH="$REPO_ROOT/.build/debug/klef"
else
    echo "build first: swift build -c release" >&2
    exit 1
fi

TEMPLATE="$REPO_ROOT/LaunchAgent/com.klef.agent.plist.template"
if [ ! -f "$TEMPLATE" ]; then
    echo "template not found: $TEMPLATE" >&2
    exit 1
fi

TARGET="$HOME/Library/LaunchAgents/com.klef.agent.plist"
mkdir -p "$(dirname "$TARGET")"

# Render the plist via Python so sed/XML metacharacters in $BINARY_PATH or
# $HOME (paths with `|`, `&`, `<`, `>`, etc.) are handled correctly. Python's
# str.replace does no metacharacter interpretation, and html.escape covers the
# XML side.
BINARY_PATH="$BINARY_PATH" HOME_PATH="$HOME" TEMPLATE="$TEMPLATE" TARGET="$TARGET" \
python3 - <<'PY'
import html, os, sys
template = open(os.environ["TEMPLATE"], "r", encoding="utf-8").read()
binary = html.escape(os.environ["BINARY_PATH"], quote=True)
home   = html.escape(os.environ["HOME_PATH"],   quote=True)
rendered = template.replace("__BINARY_PATH__", binary).replace("__HOME__", home)
with open(os.environ["TARGET"], "w", encoding="utf-8") as f:
    f.write(rendered)
PY

# Unload first if already loaded. `bootout` returns:
#   0   on success
#   36  (EBUSY)  / 113  (system code) when the label was not loaded — fine, ignore.
# Anything else is a real failure (permission, system disabled launchd domain, …)
# and should abort the install before we leave a stale plist on disk.
DOMAIN="gui/$(id -u)"
set +e
launchctl bootout "$DOMAIN/com.klef.agent" 2>/dev/null
bootout_status=$?
set -e
case $bootout_status in
    0|3|36|113) ;;  # success, or "not loaded" — both acceptable
    *)
        echo "launchctl bootout failed with status $bootout_status — aborting install." >&2
        echo "Inspect: launchctl print $DOMAIN/com.klef.agent" >&2
        exit 1
        ;;
esac

launchctl bootstrap "$DOMAIN" "$TARGET"

echo "Installed to: $TARGET"
echo "Binary: $BINARY_PATH"
echo "Logs: $HOME/Library/Logs/klef-stdout.log, klef-stderr.log"
cat <<'EOF'
After each `swift build`, the binary's code-sign hash changes and macOS may invalidate Input Monitoring permission. Re-grant in System Settings → Privacy & Security → Input Monitoring if klef stops switching.
EOF
