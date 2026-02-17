#!/bin/bash
# Restore all XFCE desktop configuration
# Run as your normal user (not root) after XFCE is installed and running
# Usage: bash shared/restore-desktop.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Restoring XFCE desktop configuration ==="
echo

# Keyboard shortcuts
echo "[1/4] Restoring keyboard shortcuts..."
bash "${SCRIPT_DIR}/xfce4-keybindings.sh"
echo

# Panel layout
echo "[2/4] Restoring panel layout..."
bash "${SCRIPT_DIR}/xfce4-panel.sh"
echo

# Display profiles
echo "[3/4] Restoring display profiles..."
mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
cp "${SCRIPT_DIR}/xfce4-displays.xml" "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml"
echo "Display profile copied."
echo

# Allow root to access X display (needed for ACPI lid script)
echo "[4/4] Enabling root X access for lid toggle..."
xhost +local:0 2>/dev/null && echo "xhost configured." || echo "WARNING: xhost failed — install x11-apps/xhost"
echo

# Apply panel changes
echo "Restarting XFCE panel..."
xfce4-panel --restart &>/dev/null &

echo
echo "=== Desktop configuration restored ==="
echo
echo "Root configuration still needed (run with sudo):"
echo "  sudo cp ${SCRIPT_DIR}/logind.conf /etc/elogind/logind.conf"
echo "  sudo cp ${SCRIPT_DIR}/acpi-lid.sh /etc/acpi/actions/lid.sh"
echo "  sudo chmod +x /etc/acpi/actions/lid.sh"
echo "  sudo cp ${SCRIPT_DIR}/acpi-default.sh /etc/acpi/default.sh"
echo "  sudo rc-service elogind restart"
echo "  sudo rc-service acpid restart"
