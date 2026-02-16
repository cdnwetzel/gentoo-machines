#!/bin/bash
# Gentoo Ultimate Harvest - XPS 9315 Edition
LOG_FILE="xps_harvest.log"

[[ $EUID -ne 0 ]] && echo "Run with sudo -E" && exit 1

echo "--- STARTING DEEP HARVEST ---" | tee "$LOG_FILE"

# 1. FIXED MODPROBED-DB
if command -v modprobed-db &> /dev/null; then
    echo "Updating database for $SUDO_USER..."
    USER=$SUDO_USER modprobed-db store
    echo "Modules: $(wc -l < /home/$SUDO_USER/.config/modprobed.db)" >> "$LOG_FILE"
fi

# 2. I2C & INPUT (The XPS Touchpad/Screen)
echo -e "\n[INPUT/I2C]" >> "$LOG_FILE"
i2cdetect -l >> "$LOG_FILE"
udevadm info --export-db | awk '/ID_INPUT_TOUCHPAD=1|ID_INPUT_TOUCHSCREEN=1/' RS= | grep -E "NAME=|DEVPATH=" >> "$LOG_FILE"

# 3. FIRMWARE (Dmesg Truth)
echo -e "\n[ACTUAL FIRMWARE IN USE]" >> "$LOG_FILE"
# This identifies what the hardware actually grabbed, not just what the driver knows
dmesg | grep -i "firmware: direct-loading" | awk '{print $NF}' | sort -u | tee -a "$LOG_FILE"

# 4. PCI & MODULES
lspci -nnk >> "$LOG_FILE"
lsmod >> "$LOG_FILE"

echo "--- DONE: Check $LOG_FILE ---"
