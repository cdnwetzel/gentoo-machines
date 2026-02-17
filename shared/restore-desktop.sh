#!/bin/bash
# Restore all XFCE desktop configuration
# Run as your normal user (not root) after XFCE is installed and running
# Usage: bash shared/restore-desktop.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Restoring XFCE desktop configuration ==="
echo

# Keyboard shortcuts
echo "[1/3] Restoring keyboard shortcuts..."
bash "${SCRIPT_DIR}/xfce4-keybindings.sh"
echo

# Panel layout
echo "[2/3] Restoring panel layout..."
bash "${SCRIPT_DIR}/xfce4-panel.sh"
echo

# Display profiles
echo "[3/3] Restoring display profiles..."
mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
cp "${SCRIPT_DIR}/xfce4-displays.xml" "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml"
echo "Display profile copied."
echo

# Apply panel changes
echo "Restarting XFCE panel..."
xfce4-panel --restart &>/dev/null &

echo
echo "=== Desktop configuration restored ==="
echo "Note: elogind config (shared/logind.conf) requires root to install:"
echo "  sudo cp shared/logind.conf /etc/elogind/logind.conf"
echo "  sudo rc-service elogind restart"
