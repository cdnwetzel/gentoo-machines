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
echo "[1/8] Installing elogind config..."
cp "${SCRIPT_DIR}/logind.conf" /etc/elogind/logind.conf
echo "Done."
echo

# ACPI lid toggle script
echo "[2/8] Installing ACPI lid toggle..."
cp "${SCRIPT_DIR}/acpi-lid.sh" /etc/acpi/actions/lid.sh
chmod +x /etc/acpi/actions/lid.sh
cp "${SCRIPT_DIR}/acpi-default.sh" /etc/acpi/default.sh
echo "Done."
echo

# LightDM display setup
echo "[3/8] Installing LightDM display setup..."
cp "${SCRIPT_DIR}/lightdm-display-setup.sh" /etc/lightdm/display-setup.sh
chmod +x /etc/lightdm/display-setup.sh
cp "${SCRIPT_DIR}/lightdm.conf" /etc/lightdm/lightdm.conf
echo "Done."
echo

# LightDM GTK greeter config (machine-specific HiDPI)
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
case "$PRODUCT" in
    *"Surface Pro 6"*)  GREETER_MACHINE_DIR="${REPO_DIR}/machines/surface-pro-6" ;;
    *"Surface Pro 9"*)  GREETER_MACHINE_DIR="${REPO_DIR}/machines/surface-pro-9" ;;
    *)                  GREETER_MACHINE_DIR="" ;;
esac
if [[ -n "$GREETER_MACHINE_DIR" && -f "$GREETER_MACHINE_DIR/lightdm-gtk-greeter.conf" ]]; then
    echo "[4/8] Installing LightDM greeter HiDPI config..."
    cp "$GREETER_MACHINE_DIR/lightdm-gtk-greeter.conf" /etc/lightdm/lightdm-gtk-greeter.conf
    echo "Done."
else
    echo "[4/8] LightDM greeter HiDPI: not needed for this display."
fi
echo

# Touchpad (tap-to-click, natural scroll)
echo "[5/8] Installing touchpad config..."
mkdir -p /etc/X11/xorg.conf.d
cp "${SCRIPT_DIR}/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
echo "Done."
echo

# KSM (Kernel Same-page Merging) startup
echo "[6/8] Installing KSM startup script..."
cp "${SCRIPT_DIR}/ksm.start" /etc/local.d/ksm.start
chmod +x /etc/local.d/ksm.start
echo "Done."
echo

# /dev/ppp device node (required for SSTP VPN / pppd)
echo "[7/8] Creating /dev/ppp device node..."
if [ ! -c /dev/ppp ]; then
    mknod /dev/ppp c 108 0
    echo "Created /dev/ppp"
else
    echo "Already exists."
fi
echo "Done."
echo

# Restart services
echo "[8/8] Restarting services..."
rc-service elogind restart
rc-service acpid restart
echo "Done."
echo

echo "=== System configuration restored ==="
echo "NOTE: Touchpad changes require X restart (logout/login or reboot)."
