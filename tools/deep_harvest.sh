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
    echo "No firmware detected via dmesg or journalctl (buffer may have rotated)." >> "$LOG_FILE"
    echo "Checking sysfs for firmware requests..." >> "$LOG_FILE"
    # Walk loaded modules and check for firmware files on disk
    for mod in $(lsmod 2>/dev/null | awk 'NR>1 {print $1}'); do
        FW_DIR=""
        case "$mod" in
            i915)       FW_DIR="i915" ;;
            iwlwifi)    FW_DIR="iwlwifi-*" ;;
            brcmfmac)   FW_DIR="brcm/brcmfmac*" ;;
            mwifiex*)   FW_DIR="mrvl/*8897*" ;;
            amdgpu)     FW_DIR="amdgpu" ;;
            nvidia*)    echo "  $mod: firmware embedded in driver" >> "$LOG_FILE"; continue ;;
            *)          continue ;;
        esac
        FILES=$(find /lib/firmware/ -path "/lib/firmware/$FW_DIR" -name '*.bin' -o -path "/lib/firmware/$FW_DIR" -name '*.ucode' 2>/dev/null | head -5)
        if [ -n "$FILES" ]; then
            echo "  $mod:" >> "$LOG_FILE"
            echo "$FILES" | sed 's/^/    /' >> "$LOG_FILE"
        fi
    done
fi

# 4. PCI DEVICES
echo -e "\n[4. PCI DEVICES]" >> "$LOG_FILE"
lspci -nnk >> "$LOG_FILE"

# 5. LOADED MODULES
echo -e "\n[5. LOADED MODULES]" >> "$LOG_FILE"
lsmod >> "$LOG_FILE"

# 6. NVIDIA GPU INFO
echo -e "\n[6. NVIDIA GPU INFO]" >> "$LOG_FILE"
if lsmod | grep -q '^nvidia ' && command -v nvidia-smi &> /dev/null; then
    nvidia-smi >> "$LOG_FILE" 2>&1
    echo "" >> "$LOG_FILE"
    # Driver version and build info
    if [ -f /proc/driver/nvidia/version ]; then
        cat /proc/driver/nvidia/version >> "$LOG_FILE"
    fi
else
    if lspci | grep -qi nvidia; then
        echo "NVIDIA GPU detected but nvidia-smi not available (nouveau or no driver loaded)" >> "$LOG_FILE"
    else
        echo "No NVIDIA GPU detected" >> "$LOG_FILE"
    fi
fi

echo "--- DONE: Check $LOG_FILE ---"
