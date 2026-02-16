#!/bin/bash
# Gentoo Ultimate Harvest - Deep Hardware Discovery
LOG_FILE="deep_harvest.log"

[[ $EUID -ne 0 ]] && echo "Run with sudo -E" && exit 1

echo "--- STARTING DEEP HARVEST ---" | tee "$LOG_FILE"

# 1. MODPROBED-DB
echo -e "\n[1. MODPROBED-DB]" >> "$LOG_FILE"
if command -v modprobed-db &> /dev/null; then
    echo "Updating database for $SUDO_USER..."
    USER=$SUDO_USER modprobed-db store
    echo "Modules: $(wc -l < /home/$SUDO_USER/.config/modprobed.db)" >> "$LOG_FILE"
else
    echo "modprobed-db not installed, skipping." >> "$LOG_FILE"
fi

# 2. I2C & INPUT (Touchpad/Touchscreen Detection)
echo -e "\n[2. INPUT/I2C]" >> "$LOG_FILE"
if command -v i2cdetect &> /dev/null; then
    i2cdetect -l >> "$LOG_FILE"
else
    echo "i2cdetect not found (install i2c-tools). Falling back to sysfs..." >> "$LOG_FILE"
    if [ -d /sys/bus/i2c/devices ]; then
        for dev in /sys/bus/i2c/devices/*; do
            [ -f "$dev/name" ] && echo "  $(basename "$dev"): $(cat "$dev/name")" >> "$LOG_FILE"
        done
    else
        echo "No I2C buses detected." >> "$LOG_FILE"
    fi
fi
udevadm info --export-db | awk '/ID_INPUT_TOUCHPAD=1|ID_INPUT_TOUCHSCREEN=1/' RS= | grep -E "NAME=|DEVPATH=" >> "$LOG_FILE"

# 3. FIRMWARE
echo -e "\n[3. ACTUAL FIRMWARE IN USE]" >> "$LOG_FILE"
# Try dmesg first, fall back to journalctl if dmesg buffer has rotated
FW_LIST=$(dmesg 2>/dev/null | grep -i "firmware: direct-loading" | awk '{print $NF}' | sort -u)

if [ -z "$FW_LIST" ] && command -v journalctl &> /dev/null; then
    FW_LIST=$(journalctl -k -b --no-pager 2>/dev/null | grep -i "firmware: direct-loading" | awk '{print $NF}' | sort -u)
fi

if [ -n "$FW_LIST" ]; then
    echo "$FW_LIST" | tee -a "$LOG_FILE"
else
    echo "No firmware detected via dmesg or journalctl." >> "$LOG_FILE"
    echo "Checking /sys/module for loaded firmware drivers..." >> "$LOG_FILE"
    ls /lib/firmware/ 2>/dev/null | head -20 >> "$LOG_FILE"
    echo "(listing truncated, check /lib/firmware/ for full contents)" >> "$LOG_FILE"
fi

# 4. PCI DEVICES
echo -e "\n[4. PCI DEVICES]" >> "$LOG_FILE"
lspci -nnk >> "$LOG_FILE"

# 5. LOADED MODULES
echo -e "\n[5. LOADED MODULES]" >> "$LOG_FILE"
lsmod >> "$LOG_FILE"

echo "--- DONE: Check $LOG_FILE ---"
