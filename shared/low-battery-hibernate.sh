#!/bin/bash
# low-battery-hibernate.sh — Hibernate when battery drops to critical level
#
# Run modes:
#   Cron:  */2 * * * * /usr/local/bin/low-battery-hibernate.sh
#   Loop:  /usr/local/bin/low-battery-hibernate.sh --loop  (from /etc/local.d/)
#
# Or run hibernate-setup.sh which installs this automatically.
# Desktops/servers with no battery exit silently (UPS uses apcupsd instead).

THRESHOLD=10  # percent (raised from 5 — need margin for 2-min polling gap)
WARN_THRESHOLD=20  # log every check at or below this level
POLL_INTERVAL=120  # seconds between checks in --loop mode
LOGFILE="/var/log/low-battery-hibernate.log"

log() {
    echo "$(date '+%F %T') $1" >> "$LOGFILE"
    logger -t low-battery -p user.warning "$1"
}

find_battery() {
    for ps in /sys/class/power_supply/*; do
        if [[ -f "$ps/type" ]] && [[ "$(cat "$ps/type")" == "Battery" ]]; then
            echo "$(basename "$ps")"
            return 0
        fi
    done
    return 1
}

check_battery() {
    local battery="$1"

    # Only act when discharging
    local status
    status=$(cat "/sys/class/power_supply/$battery/status")
    [[ "$status" != "Discharging" ]] && return 0

    local capacity
    capacity=$(cat "/sys/class/power_supply/$battery/capacity")

    # Log when battery is getting low
    if [[ "$capacity" -le "$WARN_THRESHOLD" ]]; then
        log "Battery at ${capacity}% (discharging)"
    fi

    # Hibernate at critical level
    if [[ "$capacity" -le "$THRESHOLD" ]]; then
        log "Battery at ${capacity}% — HIBERNATING"
        sync
        echo disk > /sys/power/state
    fi
}

# --- Main ---

BATTERY=$(find_battery) || exit 0  # no battery = desktop/server

if [[ "$1" == "--loop" ]]; then
    # Background loop mode (for systems without cron, e.g. SP6 via /etc/local.d/)
    log "Monitor started (PID $$, threshold=${THRESHOLD}%, poll=${POLL_INTERVAL}s)"
    while true; do
        check_battery "$BATTERY"
        sleep "$POLL_INTERVAL"
    done
else
    # Single-shot mode (for cron)
    check_battery "$BATTERY"
fi
