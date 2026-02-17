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
echo "[1/4] Installing elogind config..."
cp "${SCRIPT_DIR}/logind.conf" /etc/elogind/logind.conf
echo "Done."
echo

# ACPI lid toggle script
echo "[2/4] Installing ACPI lid toggle..."
cp "${SCRIPT_DIR}/acpi-lid.sh" /etc/acpi/actions/lid.sh
chmod +x /etc/acpi/actions/lid.sh
cp "${SCRIPT_DIR}/acpi-default.sh" /etc/acpi/default.sh
echo "Done."
echo

# LightDM display setup
echo "[3/4] Installing LightDM display setup..."
cp "${SCRIPT_DIR}/lightdm-display-setup.sh" /etc/lightdm/display-setup.sh
chmod +x /etc/lightdm/display-setup.sh
cp "${SCRIPT_DIR}/lightdm.conf" /etc/lightdm/lightdm.conf
echo "Done."
echo

# Restart services
echo "[4/4] Restarting services..."
rc-service elogind restart
rc-service acpid restart
echo "Done."
echo

echo "=== System configuration restored ==="
