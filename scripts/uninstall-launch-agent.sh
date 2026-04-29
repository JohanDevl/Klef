#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/Library/LaunchAgents/com.klef.agent.plist"

launchctl bootout "gui/$(id -u)/com.klef.agent" 2>/dev/null || true
rm -f "$TARGET"

echo "Uninstalled. Logs left in place at ~/Library/Logs/klef-{stdout,stderr}.log — remove manually if not wanted."
