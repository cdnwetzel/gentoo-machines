#!/bin/bash
# Reload mwifiex_pcie on resume — prevents WiFi hang after s2idle
# Installed to /etc/elogind/system-sleep/wifi-reload.sh
LOG="/var/log/wifi-reload.log"

case "$1" in
    pre)
        echo "$(date): pre-suspend: taking down WiFi" >> "$LOG"
        nmcli device disconnect wlp1s0 2>>"$LOG" || true
        ip link set wlp1s0 down 2>>"$LOG" || true
        modprobe -r mwifiex_pcie mwifiex 2>>"$LOG" || true
        echo "$(date): pre-suspend: modules unloaded" >> "$LOG"
        ;;
    post)
        echo "$(date): post-resume: reloading WiFi" >> "$LOG"
        # Ensure modules are fully unloaded (may have failed in pre)
        modprobe -r mwifiex_pcie mwifiex 2>>"$LOG" || true
        sleep 2
        modprobe mwifiex_pcie 2>>"$LOG"
        echo "$(date): post-resume: mwifiex_pcie loaded, waiting for firmware" >> "$LOG"
        # Wait for firmware load and interface creation
        for i in $(seq 1 10); do
            if ip link show wlp1s0 &>/dev/null; then
                echo "$(date): post-resume: wlp1s0 appeared after ${i}s" >> "$LOG"
                break
            fi
            sleep 1
        done
        # Tell NetworkManager to re-scan and reconnect
        nmcli device set wlp1s0 managed yes 2>>"$LOG" || true
        nmcli networking off 2>>"$LOG" && sleep 1 && nmcli networking on 2>>"$LOG"
        echo "$(date): post-resume: NetworkManager cycling done" >> "$LOG"
        ;;
esac
