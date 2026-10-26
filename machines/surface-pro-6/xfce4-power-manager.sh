#!/bin/bash
# XFCE4 Power Manager configuration - Surface Pro 6
# Run as your normal user (not root) after XFCE is installed
# Usage: bash machines/surface-pro-6/xfce4-power-manager.sh
#
# Timeout cascade (on battery):
#   5 min  - screen blanks (DPMS)
#   6 min  - DPMS sleep
#   7 min  - DPMS off
#   10 min - SUSPEND s2idle (xfce4-power-manager)
#   15 min - SUSPEND s2idle safety net (elogind IdleAction)
#   10%    - HIBERNATE last resort (crash = stops drain)
#   5%     - HIBERNATE last resort (low-battery-hibernate.sh)
#
# On AC: suspend at 30 min
# Hibernate crashes on SP6 but is kept as critical-battery action — crash stops drain

set -euo pipefail

echo "Configuring XFCE4 Power Manager for Surface Pro 6..."

# --- On Battery ---
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-battery -n -t int -s 5
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-sleep-on-battery -n -t int -s 6
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-off-on-battery -n -t int -s 7
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-battery -n -t int -s 10
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-sleep-mode-on-battery -n -t int -s 1

# --- On AC ---
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -n -t int -s 15
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-sleep-on-ac -n -t int -s 20
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-off-on-ac -n -t int -s 25
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -n -t int -s 30
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-sleep-mode-on-ac -n -t int -s 1

# --- Critical battery ---
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/critical-power-action -n -t int -s 2
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/critical-power-level -n -t int -s 10

# --- General ---
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -n -t bool -s true
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -n -t bool -s true
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/show-tray-icon -n -t int -s 1

# --- Screensaver idle activation (CRITICAL) ---
# xfce4-screensaver sets elogind's IdleHint via D-Bus. Without this,
# neither XFCE PM inactivity actions nor elogind IdleAction will ever fire.
xfconf-query -c xfce4-screensaver -p /saver/enabled -n -t bool -s true
xfconf-query -c xfce4-screensaver -p /saver/idle-activation/enabled -n -t bool -s true
xfconf-query -c xfce4-screensaver -p /saver/idle-activation/delay -n -t int -s 5

# --- Lid action (leave as-is for clamshell mode compatibility) ---
# HandleLidSwitchDocked=ignore in logind.conf handles lid-closed-on-dock
# Power manager lid actions left at defaults (suspend on lid close when on battery)

echo ""
echo "[OK] XFCE4 Power Manager configured."
echo ""
echo "  On battery: blank 5m, DPMS sleep/off 6/7m, SUSPEND 10m"
echo "  On AC:      blank 15m, DPMS sleep/off 20/25m, suspend 30m"
echo "  Critical:   HIBERNATE at 10% (crash = stops drain)"
echo ""
echo "  Verify: xfconf-query -c xfce4-power-manager -l -v"
