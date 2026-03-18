#!/bin/bash
# idle-hint-bridge.sh — Bridge X11 idle time to elogind IdleHint
#
# xfce4-screensaver on X11+elogind does not call SetIdleHint, so neither
# XFCE Power Manager inactivity actions nor elogind IdleAction fire.
# This script polls X11 idle time via xidletime(1) and calls SetIdleHint
# on the elogind session D-Bus interface.
#
# Deploys to: /usr/local/bin/idle-hint-bridge
# Autostart: XDG desktop file (idle-hint-bridge.desktop)
#
# Requires: xidletime (compile xidletime.c), busctl (elogind)
# Threshold: 5 minutes (matches xfce4-screensaver idle-activation/delay)

set -euo pipefail

IDLE_THRESHOLD_MS=300000  # 5 minutes in milliseconds
POLL_INTERVAL=30          # seconds between checks
IDLE_SET=false

# Locate xidletime binary
XIDLETIME=$(command -v xidletime 2>/dev/null) || {
    echo "[idle-hint-bridge] ERROR: xidletime not found"
    echo "  Compile: gcc -o xidletime xidletime.c -lX11 -lXss"
    echo "  Install: sudo cp xidletime /usr/local/bin/"
    exit 1
}

set_idle_hint() {
    local hint=$1
    local session_id
    session_id=$(loginctl --no-legend | head -1 | awk '{print $1}')
    [ -n "$session_id" ] || return 1
    busctl call org.freedesktop.login1 \
        "/org/freedesktop/login1/session/$session_id" \
        org.freedesktop.login1.Session SetIdleHint b "$hint" 2>/dev/null
}

echo "[idle-hint-bridge] Started (threshold=${IDLE_THRESHOLD_MS}ms, poll=${POLL_INTERVAL}s)"

while true; do
    idle_ms=$("$XIDLETIME" 2>/dev/null) || idle_ms=""

    if [ -z "$idle_ms" ]; then
        sleep "$POLL_INTERVAL"
        continue
    fi

    if [ "$idle_ms" -ge "$IDLE_THRESHOLD_MS" ] && [ "$IDLE_SET" = "false" ]; then
        set_idle_hint true && IDLE_SET=true
        echo "[idle-hint-bridge] Idle detected (${idle_ms}ms), IdleHint=yes"
    elif [ "$idle_ms" -lt "$IDLE_THRESHOLD_MS" ] && [ "$IDLE_SET" = "true" ]; then
        set_idle_hint false && IDLE_SET=false
        echo "[idle-hint-bridge] Activity resumed, IdleHint=no"
    fi

    sleep "$POLL_INTERVAL"
done
