#!/bin/bash

# Gentoo Hardware Harvest Script - Final Comprehensive Edition
# Purpose: Generate data for an accurate .config kernel build
# Run as: sudo ./harvest.sh

LOG_FILE="hardware_inventory.log"

# Ensure we are root for dmidecode and dmesg
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root to gather all hardware data." 
   exit 1
fi

echo "--- GENTOO HARDWARE HARVEST START ---" | tee "$LOG_FILE"
date >> "$LOG_FILE"

# 1. PCI Devices (Identify Bridge, GPU, Audio, Network)
echo -e "\n[1. PCI DEVICES - CORE HARDWARE]" >> "$LOG_FILE"
lspci -nnk >> "$LOG_FILE"

# 2. CPU Architecture (Identify P-Cores/E-Cores & Optimization Flags)
echo -e "\n[2. CPU DETAILS - SCHEDULER & OPTIMIZATION]" >> "$LOG_FILE"
lscpu | grep -E 'Model name|Vendor ID|CPU family|Model:|Flags' >> "$LOG_FILE"

# 3. Motherboard & BIOS (Identify Chipset & Laptop Specifics)
echo -e "\n[3. MOTHERBOARD/DMI - CHIPSET]" >> "$LOG_FILE"
if command -v dmidecode &> /dev/null; then
    dmidecode -t 0,2 | grep -E 'Vendor|Product Name|Version|Release Date' >> "$LOG_FILE"
else
    echo "dmidecode not found. Reading from sysfs..." >> "$LOG_FILE"
    for f in board_vendor board_name board_version bios_vendor bios_version; do
        [ -f "/sys/class/dmi/id/$f" ] && echo "$f: $(cat "/sys/class/dmi/id/$f")" >> "$LOG_FILE"
    done
fi

# 4. I2C / Touchpad / Serial Buses (Crucial for Laptops)
echo -e "\n[4. I2C / SERIAL BUSES - INPUT DEVICES]" >> "$LOG_FILE"
if [ -d /sys/bus/i2c/devices ]; then
    for dev in /sys/bus/i2c/devices/*; do
        if [ -f "$dev/name" ]; then
            echo "Bus Device: $(cat "$dev/name") ($(basename "$dev"))" >> "$LOG_FILE"
        fi
    done
else
    echo "No I2C buses detected." >> "$LOG_FILE"
fi

# 5. USB Topology
echo -e "\n[5. USB DEVICES - PERIPHERALS]" >> "$LOG_FILE"
lsusb -t >> "$LOG_FILE"

# 6. Current Module Baseline (What is working now?)
echo -e "\n[6. CURRENTLY LOADED MODULES]" >> "$LOG_FILE"
lsmod >> "$LOG_FILE"

# 7. AUTOMATED FIRMWARE SHOPPING LIST (For CONFIG_EXTRA_FIRMWARE)
echo -e "\n[7. KERNEL CONFIG SUGGESTION: FIRMWARE]" >> "$LOG_FILE"
echo "If building drivers into kernel (Y), use this list:" >> "$LOG_FILE"

# Identify firmware actually loaded by the current kernel
FW_LIST=$(dmesg | grep -i "firmware: direct-loading" | awk '{print $NF}' | sort -u | tr '\n' ' ')

if [ -n "$FW_LIST" ]; then
    echo "CONFIG_EXTRA_FIRMWARE=\"$FW_LIST\"" | tee -a "$LOG_FILE"
    echo "CONFIG_EXTRA_FIRMWARE_DIR=\"/lib/firmware\"" | tee -a "$LOG_FILE"
else
    echo "No firmware detected in dmesg. Check if your current kernel is modular." >> "$LOG_FILE"
fi

# 8. Storage Controller Check
echo -e "\n[8. STORAGE - DRIVE CONTROLLER]" >> "$LOG_FILE"
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> "$LOG_FILE"

echo -e "\n--- HARVEST COMPLETE ---"
echo "Full inventory saved to: $(pwd)/$LOG_FILE"
