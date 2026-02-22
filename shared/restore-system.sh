#!/bin/bash
# Restore system-level configuration (requires root)
# Usage: sudo bash shared/restore-system.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Restoring system configuration ==="
echo

# elogind (clamshell lid handling)
echo "[1/5] Installing elogind config..."
cp "${SCRIPT_DIR}/logind.conf" /etc/elogind/logind.conf
echo "Done."
echo

# ACPI lid toggle script
echo "[2/5] Installing ACPI lid toggle..."
cp "${SCRIPT_DIR}/acpi-lid.sh" /etc/acpi/actions/lid.sh
chmod +x /etc/acpi/actions/lid.sh
cp "${SCRIPT_DIR}/acpi-default.sh" /etc/acpi/default.sh
echo "Done."
echo

# LightDM display setup
echo "[3/5] Installing LightDM display setup..."
cp "${SCRIPT_DIR}/lightdm-display-setup.sh" /etc/lightdm/display-setup.sh
chmod +x /etc/lightdm/display-setup.sh
cp "${SCRIPT_DIR}/lightdm.conf" /etc/lightdm/lightdm.conf
echo "Done."
echo

# Touchpad (tap-to-click, natural scroll)
echo "[4/5] Installing touchpad config..."
mkdir -p /etc/X11/xorg.conf.d
cp "${SCRIPT_DIR}/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
echo "Done."
echo

# Restart services
echo "[5/5] Restarting services..."
rc-service elogind restart
rc-service acpid restart
echo "Done."
echo

echo "=== System configuration restored ==="
echo "NOTE: Touchpad changes require X restart (logout/login or reboot)."
