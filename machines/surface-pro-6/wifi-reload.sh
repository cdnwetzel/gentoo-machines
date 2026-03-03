#!/bin/bash
# Reload mwifiex_pcie on resume — prevents WiFi hang after s2idle
case "$1" in
    post)
        modprobe -r mwifiex_pcie mwifiex 2>/dev/null
        sleep 1
        modprobe mwifiex_pcie
        ;;
esac
