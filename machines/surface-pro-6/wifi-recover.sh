#!/bin/bash
# Recover Marvell 88W8897 WiFi after power save hang
# Usage: sudo wifi-recover.sh
modprobe -r mwifiex_pcie mwifiex
sleep 1
modprobe mwifiex_pcie
echo "WiFi module reloaded"
