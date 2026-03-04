#!/bin/bash
# Restore all XFCE desktop configuration
# Run as your normal user (not root) after XFCE is installed and running
# Usage: bash shared/restore-desktop.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Restoring XFCE desktop configuration ==="
echo

# Keyboard shortcuts
echo "[1/7] Restoring keyboard shortcuts..."
bash "${SCRIPT_DIR}/xfce4-keybindings.sh"
echo

# Panel layout
echo "[2/7] Restoring panel layout..."
bash "${SCRIPT_DIR}/xfce4-panel.sh"
echo

# Display profiles
echo "[3/7] Restoring display profiles..."
mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
cp "${SCRIPT_DIR}/xfce4-displays.xml" "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml"
echo "Display profile copied."
echo

# Allow root to access X display (needed for ACPI lid script)
echo "[4/7] Enabling root X access for lid toggle..."
xhost +local:0 2>/dev/null && echo "xhost configured." || echo "WARNING: xhost failed — install x11-apps/xhost"
echo

# Install xhost autostart so it persists across reboots
echo "[5/7] Installing xhost autostart entry..."
mkdir -p "${HOME}/.config/autostart"
cp "${SCRIPT_DIR}/xhost-local.desktop" "${HOME}/.config/autostart/xhost-local.desktop"
echo "Autostart entry installed."
echo

# HiDPI scaling (machine-specific)
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
case "$PRODUCT" in
    *"Surface Pro 6"*)  MACHINE_DIR="${REPO_DIR}/machines/surface-pro-6" ;;
    *"Surface Pro 9"*)  MACHINE_DIR="${REPO_DIR}/machines/surface-pro-9" ;;
    *"MacBookPro12,1"*) MACHINE_DIR="${REPO_DIR}/machines/mbp-2015" ;;
    *)                  MACHINE_DIR="" ;;
esac
if [[ -n "$MACHINE_DIR" && -f "$MACHINE_DIR/hidpi-setup.sh" ]]; then
    echo "[6/7] Applying HiDPI scaling..."
    bash "$MACHINE_DIR/hidpi-setup.sh"
    echo
else
    echo "[6/7] HiDPI scaling: not needed for this display."
    echo
fi

# PipeWire audio session autostart
echo "[7/7] Installing PipeWire autostart entry..."
mkdir -p "${HOME}/.config/autostart"
cat > "${HOME}/.config/autostart/pipewire.desktop" << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=PipeWire
Exec=gentoo-pipewire-launcher
Hidden=false
X-XFCE-Autostart-Override=true
DESKTOP
echo "PipeWire autostart installed."
echo

# Apply panel changes
echo "Restarting XFCE panel..."
xfce4-panel --restart &>/dev/null &

echo
echo "=== Desktop configuration restored ==="
echo
echo "Now run the system-level restore (requires root):"
echo "  sudo bash ${SCRIPT_DIR}/restore-system.sh"
